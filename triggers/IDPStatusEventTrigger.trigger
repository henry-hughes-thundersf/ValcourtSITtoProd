trigger IDPStatusEventTrigger on IDP_Status_Event__e (after insert) {
	IDPStatusEventTriggerHandler.handleAfterInsert(Trigger.New);
}