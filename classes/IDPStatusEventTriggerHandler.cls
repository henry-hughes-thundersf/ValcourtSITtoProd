/**
 * Handler: IDPStatusEventTriggerHandler
 *
 * Responsibility: react to IDP_Status_Event__e platform events.
 *   - Status == 'Failed'  -> create an MuleSoft_Error_Log__c record
 *   - Status == 'Completed' (or anything else) -> no-op
 */
public with sharing class IDPStatusEventTriggerHandler {

    private static final String STATUS_FAILED = 'Failed';

    public static void handleAfterInsert(List<IDP_Status_Event__e> newEvents) {
        updateOpportunities(newEvents);
        
        List<MuleSoft_Error_Log__c> logsToInsert = buildErrorLogs(newEvents);

        if (logsToInsert.isEmpty()) {
            return;
        }

        insertErrorLogs(logsToInsert);
    }
    
    private static void updateOpportunities(List<IDP_Status_Event__e> events) {
        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        
        for (IDP_Status_Event__e evt : events) {
            if (String.isBlank(evt.Opportunity_Id__c)) {
                System.debug(LoggingLevel.WARN, 'IDP_Status_Event__e received with no Opportunity_Id__c — skipping Opportunity update. ContentVersionId: ' + evt.Content_Version_Id__c);
                continue;
            }
            
            String idpRFI = null;
            
            if(String.isNotBlank(evt.IDP_RFI__c)) {
                idpRFI = evt.IDP_RFI__c;
            }
            
            oppsToUpdate.add(new Opportunity(
                Id = evt.Opportunity_Id__c,
                IDP_Status__c = evt.IDP_Status__c,
                IDP_RFI__c = idpRFI
            ));
        }
        
        if (oppsToUpdate.isEmpty()) {
            return;
        }
        
        List<Database.SaveResult> results = Database.update(oppsToUpdate, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Database.Error err : results[i].getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'Failed to update Opportunity ' + oppsToUpdate[i].Id + ' | ' + err.getStatusCode() + ': ' + err.getMessage());
                }
            }
        }
    }

    private static List<MuleSoft_Error_Log__c> buildErrorLogs(List<IDP_Status_Event__e> events) {
        List<MuleSoft_Error_Log__c> logs = new List<MuleSoft_Error_Log__c>();

        for (IDP_Status_Event__e evt : events) {
            if (evt.IDP_Status__c != STATUS_FAILED) {
                continue;
            }

            logs.add(new MuleSoft_Error_Log__c(
                Opportunity__c        = evt.Opportunity_Id__c,
                Content_Version_Id__c = evt.Content_Version_Id__c,
                Error_Message__c      = evt.IDP_Error__c
            ));
        }

        return logs;
    }

    private static void insertErrorLogs(List<MuleSoft_Error_Log__c> logs) {
        List<Database.SaveResult> results = Database.insert(logs, false);

        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Database.Error err : results[i].getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'Failed to insert MuleSoft_Error_Log__c for Opportunity ' + logs[i].Opportunity__c + ' | ' + err.getStatusCode() + ': ' + err.getMessage());
                }
            }
        }
    }
}