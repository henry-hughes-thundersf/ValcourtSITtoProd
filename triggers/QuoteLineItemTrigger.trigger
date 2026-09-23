trigger QuoteLineItemTrigger on QuoteLineItem (
    after insert,
    after update,
    after delete,
    after undelete,
    before insert,
    before update
) {
    if (Trigger.isAfter) {
        QuoteLineItemTriggerHandler.rollupAmendmentPricing(
            Trigger.new,
            Trigger.oldMap
        );
    }
    
    if (Trigger.isBefore) {
        QuoteLineItemTriggerHandler.calculateFirstYearContractValue(Trigger.new);
        if (Trigger.isInsert || Trigger.isUpdate) {
            QuoteLineItemTriggerHandler.processCostOverrides(
                Trigger.new,
                Trigger.oldMap
            );
        }
    }
}