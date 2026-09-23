public class QuoteLineItemTriggerHandler {

    private static final String WINDOW_CLEANING_QUOTE_RECORD_TYPE = 'Window_Cleaning';
    
    private static final String  STATUS_WARN            = 'Warning';
    private static final String  STATUS_REVIEW          = 'Flagged';

    private static final Boolean THRESHOLDS_ARE_PERCENT = true;
    private static final Boolean CLEAR_WARN_ONLY        = false;

    private static final Integer HISTORY_QUERY_LIMIT    = 10000;

    private static Set<Id> getWindowCleaningQuoteIds(
        List<QuoteLineItem> newList,
        Map<Id, QuoteLineItem> oldMap
    ) {
        Set<Id> quoteIds = new Set<Id>();

        if (newList != null) {
            for (QuoteLineItem qli : newList) {
                if (qli != null && qli.QuoteId != null) {
                    quoteIds.add(qli.QuoteId);
                }
            }
        }

        if (oldMap != null) {
            for (QuoteLineItem qli : oldMap.values()) {
                if (qli != null && qli.QuoteId != null) {
                    quoteIds.add(qli.QuoteId);
                }
            }
        }

        Set<Id> windowCleaningQuoteIds = new Set<Id>();

        if (quoteIds.isEmpty()) {
            return windowCleaningQuoteIds;
        }

        for (Quote q : [
            SELECT Id
            FROM Quote
            WHERE Id IN :quoteIds
              AND RecordType.DeveloperName = :WINDOW_CLEANING_QUOTE_RECORD_TYPE
        ]) {
            windowCleaningQuoteIds.add(q.Id);
        }

        return windowCleaningQuoteIds;
    }

    public static void rollupAmendmentPricing(
        List<QuoteLineItem> newList,
        Map<Id, QuoteLineItem> oldMap
    ) {
        Set<Id> dimensionIds = new Set<Id>();

        // From new records
        if (newList != null) {
            for (QuoteLineItem qli : newList) {
                if (qli != null && qli.Quote_Dimension__c != null) {
                    dimensionIds.add(qli.Quote_Dimension__c);
                }
            }
        }

        // From old records
        if (oldMap != null) {
            for (QuoteLineItem oldQli : oldMap.values()) {
                if (oldQli != null && oldQli.Quote_Dimension__c != null) {
                    dimensionIds.add(oldQli.Quote_Dimension__c);
                }
            }
        }

        if (dimensionIds.isEmpty()) {
            return;
        }

        // Aggregate positive Subtotal values only
        Map<Id, Decimal> dimensionToTotal = new Map<Id, Decimal>();

        for (AggregateResult ar : [
            SELECT Quote_Dimension__c dimensionId,
                   SUM(Subtotal) total
            FROM QuoteLineItem
            WHERE Quote_Dimension__c IN :dimensionIds
              AND Subtotal > 0
            GROUP BY Quote_Dimension__c
        ]) {
            dimensionToTotal.put(
                (Id) ar.get('dimensionId'),
                (Decimal) ar.get('total')
            );
        }

        // Prepare updates
        List<Quote_Dimension__c> dimensionsToUpdate = new List<Quote_Dimension__c>();

        for (Id dimId : dimensionIds) {
            Decimal total = dimensionToTotal.containsKey(dimId)
                ? dimensionToTotal.get(dimId)
                : 0;

            dimensionsToUpdate.add(new Quote_Dimension__c(
                Id = dimId,
                Amendment_Total_Price__c = total
            ));
        }

        if (!dimensionsToUpdate.isEmpty()) {
            update dimensionsToUpdate;
        }
    }

    public static void calculateFirstYearContractValue(List<QuoteLineItem> newList) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Set<Id> windowCleaningQuoteIds = getWindowCleaningQuoteIds(newList, null);

        if (windowCleaningQuoteIds.isEmpty()) {
            return;
        }

        List<QuoteLineItem> targetQuoteLines = new List<QuoteLineItem>();

        for (QuoteLineItem qli : newList) {
            if (
                qli != null
                && qli.QuoteId != null
                && windowCleaningQuoteIds.contains(qli.QuoteId)
            ) {
                targetQuoteLines.add(qli);
            }
        }

        if (targetQuoteLines.isEmpty()) {
            return;
        }

        Set<Id> quoteIds = new Set<Id>();
        Set<Id> dimensionIds = new Set<Id>();
        Set<Id> amendedContractLineItemIds = new Set<Id>();

        for (QuoteLineItem qli : targetQuoteLines) {
            quoteIds.add(qli.QuoteId);

            if (qli.Quote_Dimension__c != null) {
                dimensionIds.add(qli.Quote_Dimension__c);
            }

            if (qli.Amended_Contract_Line_Item__c != null) {
                amendedContractLineItemIds.add(qli.Amended_Contract_Line_Item__c);
            }
        }

        Map<Id, Quote> quoteMap = new Map<Id, Quote>([
            SELECT Id,
                   Start_Date__c,
                   End_Date__c,
                   Term__c,
                   Amended_Contract__r.StartDate,
                   Amended_Contract__r.ContractTerm
            FROM Quote
            WHERE Id IN :quoteIds
        ]);

        Map<Id, Quote_Dimension__c> dimensionMap = new Map<Id, Quote_Dimension__c>();

        if (!dimensionIds.isEmpty()) {
            dimensionMap = new Map<Id, Quote_Dimension__c>([
                SELECT Id,
                       Start_Date__c,
                       End_Date__c,
                       Term__c
                FROM Quote_Dimension__c
                WHERE Id IN :dimensionIds
            ]);
        }

        Map<Id, Contract_Line_Item__c> amendedCliMap = new Map<Id, Contract_Line_Item__c>();

        if (!amendedContractLineItemIds.isEmpty()) {
            amendedCliMap = new Map<Id, Contract_Line_Item__c>([
                SELECT Id,
                       Contract__c,
                       Contract__r.StartDate,
                       Start_Date__c,
                       End_Date__c
                FROM Contract_Line_Item__c
                WHERE Id IN :amendedContractLineItemIds
            ]);
        }

        for (QuoteLineItem qli : targetQuoteLines) {
            Quote quote = quoteMap.get(qli.QuoteId);
            Date effectiveFirstYearEndDate;

            if (qli.Amended_Contract_Line_Item__c != null) {
                Contract_Line_Item__c acli = amendedCliMap.get(qli.Amended_Contract_Line_Item__c);

                if (
                    acli != null
                    && acli.Contract__r != null
                    && acli.Contract__r.StartDate != null
                ) {
                    effectiveFirstYearEndDate = acli.Contract__r.StartDate.addMonths(12).addDays(-1);
                }
            }

            if (effectiveFirstYearEndDate == null && quote != null && quote.Start_Date__c != null) {
                effectiveFirstYearEndDate = quote.Start_Date__c.addMonths(12).addDays(-1);
            }

            if (effectiveFirstYearEndDate == null && qli.Quote_Dimension__c != null) {
                Quote_Dimension__c dimension = dimensionMap.get(qli.Quote_Dimension__c);

                if (dimension != null && dimension.Start_Date__c != null) {
                    effectiveFirstYearEndDate = dimension.Start_Date__c.addMonths(12).addDays(-1);
                }
            }

            if (effectiveFirstYearEndDate == null && qli.ServiceDate != null) {
                effectiveFirstYearEndDate = qli.ServiceDate.addMonths(12).addDays(-1);
            }

            if (effectiveFirstYearEndDate == null) {
                qli.Contract_Value_Year1__c = null;
                continue;
            }

            if (qli.End_Date__c != null && qli.End_Date__c < effectiveFirstYearEndDate) {
                effectiveFirstYearEndDate = qli.End_Date__c;
            }

            if (qli.ServiceDate == null || qli.Final_Price__c == null) {
                qli.Contract_Value_Year1__c = null;
                continue;
            }

            Integer quantity = 0;
            System.debug('first year end date: ' + effectiveFirstYearEndDate);

            if (qli.ServiceDate < effectiveFirstYearEndDate) {
                Decimal effectiveFirstYearWorkOrderCount = 0;
                Quote_Dimension__c dimension = qli.Quote_Dimension__c != null ? dimensionMap.get(qli.Quote_Dimension__c) : null;

                if (
                    qli.Type__c == 'Amendment' 
                    || (dimension != null && dimension.End_Date__c != null && dimension.End_Date__c <= effectiveFirstYearEndDate) 
                    || (dimension == null && qli.End_Date__c != null && qli.End_Date__c <= effectiveFirstYearEndDate)
                ) {
                    quantity = qli.Quantity != null ? Integer.valueOf(qli.Quantity) : 0;
                    effectiveFirstYearWorkOrderCount = quantity;
                    System.debug('term portion not used');
                } else {
                    if (qli.Frequency__c == 'Off Frequency' && qli.Off_Frequency_Dates__c != null) {
                        // do off frequency date calc
                        quantity = Integer.valueOf(getFirstYearOffFrequencyCount(qli.Off_Frequency_Dates__c, effectiveFirstYearEndDate));
                    } else if (!String.isBlank(qli.Frequency__c)) {
                        ConversionUtility util = new ConversionUtility();
                        quantity = util.getFrequencyWorkOrderCount(qli.Frequency__c);
                    }

                    Decimal firstYearTerm = getTermBetweenDates(qli.ServiceDate, effectiveFirstYearEndDate);
                    Integer effectiveFirstYearTerm = firstYearTerm != null ? Integer.valueOf(firstYearTerm) : 0;

                    System.debug('effective first year term: ' + effectiveFirstYearTerm);
                    System.debug('term portion: ' + (effectiveFirstYearTerm / 12.0));

                    effectiveFirstYearWorkOrderCount = (effectiveFirstYearTerm / 12.0) * quantity;
                }

                System.debug('is first year');
                System.debug('quantity: ' + quantity);
                System.debug('first year work order count: ' + effectiveFirstYearWorkOrderCount);

                qli.Contract_Value_Year1__c = (qli.Final_Price__c * effectiveFirstYearWorkOrderCount).setScale(0);
            } else {
                System.debug('is not first year');
                qli.Contract_Value_Year1__c = null;
            }

            /* this is the original conditional logic
            //else {
            Quote quote = quoteMap.get(qli.QuoteId);
            Decimal totalTerm = getTotalTerm(quote);
            Date firstYearEndDate = quote.Amended_Contract__r != null && quote.Amended_Contract__r.StartDate != null 
                                        ? quote.Amended_Contract__r.StartDate 
                                        : quote.Start_Date__c;
            if (firstYearEndDate != null) {
                firstYearEndDate = firstYearEndDate.addMonths(12).addDays(-1);
            }
            if (totalTerm <= 12 || (firstYearEndDate != null && qli.End_Date__c <= firstYearEndDate)) {
                qli.Contract_Value_Year1__c = qli.Final_Price__c * qli.Quantity;
            } else if (firstYearEndDate != null && qli.ServiceDate < firstYearEndDate) {
                if (qli.Frequency__c == 'Off Frequency' && qli.Off_Frequency_Dates__c != null) {
                    // do off frequency date calc
                    Decimal offQuantity = getFirstYearOffFrequencyCount(qli.Off_Frequency_Dates__c, firstYearEndDate);
                    qli.Contract_Value_Year1__c = (qli.Final_Price__c * offQuantity).setScale(0);
                } else {
                    // do partial year calc
                    Decimal partialYearTerm = getTermBetweenDates(qli.ServiceDate, firstYearEndDate);
                    Quote_Dimension__c dimension = qli.Quote_Dimension__c != null ? dimensionMap.get(qli.Quote_Dimension__c) : null;
                    Decimal quoteLineTerm = getQuoteLineTerm(qli, dimension);
                    Decimal partialQuantityFactor = (12 / partialYearTerm) * (quoteLineTerm > 12 ? 12 / quoteLineTerm : 1);
                    Decimal partialQuantity = partialQuantityFactor * qli.Quantity;
                    qli.Contract_Value_Year1__c = (qli.Final_Price__c * partialQuantity).setScale(0);
                }
            } else {
                qli.Contract_Value_Year1__c = null;
            }

            //}
            */
        }
    }

    /* related to old process
    private static Decimal getTotalTerm(Quote quote) {
        Decimal term = quote.Term__c;
        if (quote.Amended_Contract__r.ContractTerm != null) {
            term = quote.Amended_Contract__r.ContractTerm;
        }
        return term;
    }

    private static Decimal getQuoteLineTerm(QuoteLineItem qli, Quote_Dimension__c dimension) {
        Decimal term;
        if (dimension != null && dimension.Term__c != null) {
            term = dimension.Term__c;
        } else {
            term = getTermBetweenDates(qli.ServiceDate, qli.End_Date__c);
        }
        return term;
    }*/

    private static Decimal getTermBetweenDates(Date startDate, Date endDate) {
        Decimal term = null;

        if (startDate != null && endDate != null) {
            if (endDate.year() == startDate.year()) {
                term = endDate.month() - startDate.month() + 1;
            } else {
                if (endDate.month() == startDate.month() && endDate.day() < startDate.day()) {
                    term = 12;
                } else {
                    term = 13;
                }

                term = term - startDate.month() + endDate.month() + ((endDate.year() - startDate.year() - 1) * 12);
            }
        }

        return term;
    }

    private static Decimal getFirstYearOffFrequencyCount(String offFrequencyDateString, Date firstYearEndDate) {
        ConversionUtility util = new ConversionUtility();
        List<Date> dates = util.extractDateListFromString(offFrequencyDateString);
        Decimal count = 0;

        for (Date dt : dates) {
            if (dt <= firstYearEndDate) {
                count++;
            }
        }

        return count;
    }
    
    private class VarianceMetric {
        public String  label;                       // used as the history map key
        public String  baseField;                   // the expected / standard value
        public String  compareField;                // the entered / overridden value
        public Boolean adverseWhenCompareIsHigher;  // which direction is "bad"
        public Boolean asPercentOfBase;             // true = % of base, false = raw point difference

        public VarianceMetric(String label,
                              String baseField,
                              String compareField,
                              Boolean adverseWhenCompareIsHigher,
                              Boolean asPercentOfBase) {
            this.label                      = label;
            this.baseField                  = baseField;
            this.compareField               = compareField;
            this.adverseWhenCompareIsHigher = adverseWhenCompareIsHigher;
            this.asPercentOfBase            = asPercentOfBase;
        }
    }

    private static final List<VarianceMetric> METRICS = new List<VarianceMetric>{

        // Overriding the unit cost UPWARDS is adverse. Measured as % of unit cost.
        new VarianceMetric('Unit Cost',
                           'WP_Unit_Cost__c',
                           'WP_Override_Unit_Cost__c',
                           true,
                           true),

        new VarianceMetric('Margin',
                           'Proposal_Target_Margin__c',
                           'WP_MarginPercent__c',
                           true,
                           true),

        new VarianceMetric('Conversion Rate',
                           'WP_Conversion_Factor__c',
                           'WP_Override_Conversion_Production_Rate__c',
                           true,
                           true)
    };

    public static void processCostOverrides(List<QuoteLineItem> newList,
                                            Map<Id, QuoteLineItem> oldMap) {                                                

        if (newList == null || newList.isEmpty()) {
            return;
        }
                                          
        Flag_Override_Cost_Settings__c settings = Flag_Override_Cost_Settings__c.getOrgDefaults();

        if (settings == null || settings.Warn_Status_Threshold__c == null) {
            return;
        }

        Decimal warnThreshold  = settings.Warn_Status_Threshold__c;
        Decimal precedentPct   = settings.Historical_Records_Precedent_Pct_Require__c;
        Integer historyCount   = settings.Number_Of_Historical_Records__c == null
                                 ? 0
                                 : Integer.valueOf(settings.Number_Of_Historical_Records__c);

        List<QuoteLineItem>        toEvaluate = new List<QuoteLineItem>();
        List<Map<String, Decimal>> varianceByMetricPerLine = new List<Map<String, Decimal>>();

        Set<Id> productIds = new Set<Id>();
        Set<Id> excludeIds = new Set<Id>();
                                                
			
        for (QuoteLineItem qli : newList) {
            
            if (qli == null) {
                continue;
            }

            QuoteLineItem oldQli = (oldMap == null) ? null : oldMap.get(qli.Id);
            
            if (!hasRelevantChange(qli, oldQli)) {
                continue;
            }
            
            // Every metric that can actually be measured on this line
            Map<String, Decimal> variances = getVariances(qli);

            if (variances.isEmpty()) {
                continue;   // nothing comparable populated - leave Warn_Status__c untouched
            }

            toEvaluate.add(qli);
            varianceByMetricPerLine.add(variances);

            // History is only needed when at least one metric is adverse
            if (hasAdverseVariance(variances)) {
                if (qli.Product2Id != null) {
                    productIds.add(qli.Product2Id);
                }
                if (qli.Id != null) {
                    excludeIds.add(qli.Id);
                }
            }
        }

        if (toEvaluate.isEmpty()) {
            return;
        }
                                                                                                                                            
        // productId -> metric label -> newest N variances
        Map<Id, Map<String, List<Decimal>>> historyByProduct =
            getHistoricalVariancesByProduct(productIds, excludeIds, historyCount);
            
                                                
        for (Integer i = 0; i < toEvaluate.size(); i++) {

            QuoteLineItem        qli       = toEvaluate[i];
            Map<String, Decimal> variances = varianceByMetricPerLine[i];
            System.debug('variances   ' + variances);
            Map<String, List<Decimal>> productHistory =
                (qli.Product2Id == null) ? null : historyByProduct.get(qli.Product2Id);
      			
            String resultFlag = null;   // null = no flag needed

            // ANY metric breaching is enough to flag; Review beats Warn.
            for (VarianceMetric metric : METRICS) {

                Decimal variance = variances.get(metric.label);

                if (variance == null || variance <= 0) {
                    continue;   // not populated, or on the good side of the base value
                }

                String flag = (variance >= warnThreshold) ? STATUS_REVIEW : STATUS_WARN;
                System.debug('flag   ' +flag+ '  ' + metric.label);
                System.debug('metric.label   ' + metric.label);

                List<Decimal> metricHistory =
                    (productHistory == null) ? null : productHistory.get(metric.label);

                Boolean clearedByHistory =  historyCount > 0
                    && precedentPct != null
                    && hasEnoughHigherOverrides(variance, metricHistory, precedentPct);
                System.debug('clearedByHistory  ' + clearedByHistory);
                if (clearedByHistory) {
                    continue;   // precedent exists for this metric - it does not flag
                }

                if (flag == STATUS_REVIEW) {
                    resultFlag = STATUS_REVIEW;
                    break;      // worst case reached, no need to look further
                }

                resultFlag = STATUS_WARN;
            }

            qli.Warn_Status__c = resultFlag;
            
        }
    }

    /**
     * True when this is an insert, or when either side of any metric changed.
     */
    @TestVisible
    private static Boolean hasRelevantChange(QuoteLineItem qli, QuoteLineItem oldQli) {

        if (oldQli == null) {
            return true;
        }

        for (VarianceMetric metric : METRICS) {
            if (isDifferent((Decimal) qli.get(metric.baseField),
                            (Decimal) oldQli.get(metric.baseField))) {
                return true;
            }
            if (isDifferent((Decimal) qli.get(metric.compareField),
                            (Decimal) oldQli.get(metric.compareField))) {
                return true;
            }
        }

        return false;
    }

    private static Boolean isDifferent(Decimal a, Decimal b) {

        if (a == null && b == null) {
            return false;
        }
        if (a == null || b == null) {
            return true;
        }
        return a != b;
    }

    @TestVisible
    private static Map<String, Decimal> getVariances(QuoteLineItem qli) {

        Map<String, Decimal> variances = new Map<String, Decimal>();

        for (VarianceMetric metric : METRICS) {
            Decimal variance = calculateVariance(metric, qli);
            if (variance != null) {
                variances.put(metric.label, variance);
            }
        }

        return variances;
    }

    private static Boolean hasAdverseVariance(Map<String, Decimal> variances) {

        for (Decimal variance : variances.values()) {
            if (variance != null && variance > 0) {
                return true;
            }
        }
        return false;
    }

    @TestVisible
    private static Decimal calculateVariance(VarianceMetric metric, QuoteLineItem qli) {

        Decimal baseValue    = (Decimal) qli.get(metric.baseField);
        Decimal compareValue = (Decimal) qli.get(metric.compareField);

        if (baseValue == null || compareValue == null) {
            return null;
        }

        Decimal delta = metric.adverseWhenCompareIsHigher
                        ? (compareValue - baseValue)
                        : (baseValue - compareValue);

        if (metric.asPercentOfBase) {
            if (baseValue == 0) {
                return null;   // avoid divide by zero
            }
            delta = (delta / Math.abs(baseValue)) * 100;
        }

        return delta.setScale(4, System.RoundingMode.HALF_UP);
    }


    @TestVisible
    private static Decimal calculateVariance(Decimal unitCost, Decimal unitCostOverride) {

        Decimal delta = unitCostOverride - unitCost;

        if (THRESHOLDS_ARE_PERCENT) {
            delta = (delta / unitCost) * 100;
        }
        return delta.setScale(4, System.RoundingMode.HALF_UP);
    }

    @TestVisible
    private static Boolean hasEnoughHigherOverrides(Decimal variance,
                                                    List<Decimal> historicalVariances,
                                                    Decimal requiredPercent) {

        if (historicalVariances == null || historicalVariances.isEmpty()) {
            return false;
        }

        Integer higherCount = 0;
        for (Decimal v : historicalVariances) {
            if (v > variance) {
                higherCount++;
            }
        }

        Decimal actualPercent =
            (Decimal.valueOf(higherCount) / Decimal.valueOf(historicalVariances.size())) * 100;

        return actualPercent >= requiredPercent;
    }

    private static Map<Id, Map<String, List<Decimal>>> getHistoricalVariancesByProduct(
        Set<Id> productIds,
        Set<Id> excludeIds,
        Integer historyCount
    ) {
        Map<Id, Map<String, List<Decimal>>> result = new Map<Id, Map<String, List<Decimal>>>();

        if (productIds.isEmpty() || historyCount <= 0) {
            return result;
        }

        for (QuoteLineItem hist : [
                SELECT Id, Product2Id, CreatedDate, Quote.Opportunity.StageName,
                       WP_Unit_Cost__c,
                       WP_Override_Unit_Cost__c,
                       Proposal_Target_Margin__c,
                       WP_MarginPercent__c,
                       WP_Conversion_Factor__c,
                       WP_Override_Conversion_Production_Rate__c
                FROM   QuoteLineItem
                WHERE  Product2Id IN :productIds
                AND    Id NOT IN :excludeIds
                AND    (WP_Override_Unit_Cost__c != null
                        OR WP_MarginPercent__c != null
                        OR WP_Override_Conversion_Production_Rate__c != null)
                ORDER BY Product2Id, CreatedDate DESC
                LIMIT :HISTORY_QUERY_LIMIT ]) {

            Map<String, List<Decimal>> byMetric = result.get(hist.Product2Id);

            if (byMetric == null) {
                byMetric = new Map<String, List<Decimal>>();
                result.put(hist.Product2Id, byMetric);
            }

            for (VarianceMetric metric : METRICS) {

                Decimal variance = calculateVariance(metric, hist);

                if (variance == null) {
                    continue;
                }

                List<Decimal> variances = byMetric.get(metric.label);

                if (variances == null) {
                    variances = new List<Decimal>();
                    byMetric.put(metric.label, variances);
                }

                if (variances.size() < historyCount) {   // newest N only
                    variances.add(variance);
                }
            }
        }

        return result;
    }
  
}