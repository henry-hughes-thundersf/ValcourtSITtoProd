@isTest
private class IDPStatusEventTriggerHandlerTest {

    @TestSetup
    static void setup() {
        insert new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
    }

    @isTest
    static void testFailedStatus_CreatesErrorLogAndUpdatesOpportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        IDP_Status_Event__e evt = new IDP_Status_Event__e(
            Opportunity_Id__c     = opp.Id,
            Content_Version_Id__c = '0684x000001AbcAAE',
            IDP_Status__c         = 'Failed',
            IDP_Error__c          = 'Some error message'
        );

        Test.startTest();
        IDPStatusEventTriggerHandler.handleAfterInsert(new List<IDP_Status_Event__e>{ evt });
        Test.stopTest();

        Opportunity updatedOpp = [SELECT Id, IDP_Status__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Failed', updatedOpp.IDP_Status__c, 'Opportunity status should be updated to Failed');

        List<MuleSoft_Error_Log__c> logs = [
            SELECT Id, Opportunity__c, Content_Version_Id__c, Error_Message__c
            FROM MuleSoft_Error_Log__c
        ];
        System.assertEquals(1, logs.size(), 'One error log should be created for the Failed event');
        System.assertEquals(opp.Id, logs[0].Opportunity__c);
        System.assertEquals('0684x000001AbcAAE', logs[0].Content_Version_Id__c);
        System.assertEquals('Some error message', logs[0].Error_Message__c);
    }

    @isTest
    static void testCompletedStatus_UpdatesOpportunityButNoErrorLog() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        IDP_Status_Event__e evt = new IDP_Status_Event__e(
            Opportunity_Id__c     = opp.Id,
            Content_Version_Id__c = '0684x000001AbcAAE',
            IDP_Status__c         = 'Completed',
            IDP_Error__c          = null
        );

        Test.startTest();
        IDPStatusEventTriggerHandler.handleAfterInsert(new List<IDP_Status_Event__e>{ evt });
        Test.stopTest();

        Opportunity updatedOpp = [SELECT Id, IDP_Status__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Completed', updatedOpp.IDP_Status__c);

        List<MuleSoft_Error_Log__c> logs = [SELECT Id FROM MuleSoft_Error_Log__c];
        System.assertEquals(0, logs.size(), 'No error log should be created for a non-Failed status');
    }

    @isTest
    static void testBlankOpportunityId_SkipsOpportunityUpdateButStillLogsError() {
        IDP_Status_Event__e evt = new IDP_Status_Event__e(
            Opportunity_Id__c     = null,
            Content_Version_Id__c = '0684x000001AbcAAE',
            IDP_Status__c         = 'Failed',
            IDP_Error__c          = 'Error with no opportunity id'
        );

        Test.startTest();
        IDPStatusEventTriggerHandler.handleAfterInsert(new List<IDP_Status_Event__e>{ evt });
        Test.stopTest();
        List<MuleSoft_Error_Log__c> logs = [
            SELECT Id, Opportunity__c, Error_Message__c FROM MuleSoft_Error_Log__c
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals(null, logs[0].Opportunity__c);
        System.assertEquals('Error with no opportunity id', logs[0].Error_Message__c);
    }

    @isTest
    static void testInvalidOpportunityId_DmlFailuresAreHandledGracefully() {
        Id fakeOppId = '006000000000000AAA';

        IDP_Status_Event__e evt = new IDP_Status_Event__e(
            Opportunity_Id__c     = fakeOppId,
            Content_Version_Id__c = '0684x000001AbcAAE',
            IDP_Status__c         = 'Failed',
            IDP_Error__c          = 'Error for nonexistent opportunity'
        );

        Test.startTest();
        try {
            IDPStatusEventTriggerHandler.handleAfterInsert(new List<IDP_Status_Event__e>{ evt });
        } catch (Exception e) {
            System.assert(false, 'Handler should not throw when DML against a non-existent Opportunity fails: ' + e.getMessage());
        }
        Test.stopTest();
        List<MuleSoft_Error_Log__c> logs = [SELECT Id FROM MuleSoft_Error_Log__c];
        System.assertEquals(0, logs.size(), 'Error log insert should fail gracefully against a non-existent Opportunity lookup');
    }

    @isTest
    static void testMultipleEvents_BulkProcessing() {
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 5; i++) {
            opps.add(new Opportunity(
                Name = 'Bulk Opp ' + i,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            ));
        }
        insert opps;

        List<IDP_Status_Event__e> events = new List<IDP_Status_Event__e>();
        for (Integer i = 0; i < opps.size(); i++) {
            Boolean isFailed = Math.mod(i, 2) == 0;
            events.add(new IDP_Status_Event__e(
                Opportunity_Id__c     = opps[i].Id,
                Content_Version_Id__c = '0684x000001Abc' + i + 'AAE',
                IDP_Status__c         = isFailed ? 'Failed' : 'Completed',
                IDP_Error__c          = isFailed ? 'Error ' + i : null
            ));
        }

        Test.startTest();
        IDPStatusEventTriggerHandler.handleAfterInsert(events);
        Test.stopTest();
        List<MuleSoft_Error_Log__c> logs = [SELECT Id FROM MuleSoft_Error_Log__c];
        System.assertEquals(3, logs.size());

        List<Opportunity> updatedOpps = [
            SELECT Id, IDP_Status__c FROM Opportunity WHERE Id IN :opps
        ];
        System.assertEquals(5, updatedOpps.size());
        for (Opportunity o : updatedOpps) {
            System.assertNotEquals(null, o.IDP_Status__c);
        }
    }

    @isTest
    static void testEmptyEventList_NoExceptionAndNoRecordsCreated() {
        Test.startTest();
        IDPStatusEventTriggerHandler.handleAfterInsert(new List<IDP_Status_Event__e>());
        Test.stopTest();

        List<MuleSoft_Error_Log__c> logs = [SELECT Id FROM MuleSoft_Error_Log__c];
        System.assertEquals(0, logs.size());
    }

    
    @isTest
    static void testTrigger_PublishAndDeliverEvent_InvokesHandler() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        IDP_Status_Event__e evt = new IDP_Status_Event__e(
            Opportunity_Id__c     = opp.Id,
            Content_Version_Id__c = '0684x000001AbcAAE',
            IDP_Status__c         = 'Failed',
            IDP_Error__c          = 'Trigger coverage test error'
        );

        Test.startTest();
        Database.SaveResult sr = EventBus.publish(evt);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assert(sr.isSuccess(), 'Platform event should publish successfully');

        Opportunity updatedOpp = [SELECT Id, IDP_Status__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Failed', updatedOpp.IDP_Status__c, 'Trigger should have invoked handler and updated Opportunity');

        List<MuleSoft_Error_Log__c> logs = [SELECT Id, Opportunity__c, Error_Message__c FROM MuleSoft_Error_Log__c];
        System.assertEquals(1, logs.size(), 'Trigger should have invoked handler and created an error log');
        System.assertEquals(opp.Id, logs[0].Opportunity__c);
        System.assertEquals('Trigger coverage test error', logs[0].Error_Message__c);
    }

    
    @isTest
    static void testTrigger_PublishMultipleEvents_BulkDelivery() {
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 3; i++) {
            opps.add(new Opportunity(
                Name = 'Trigger Bulk Opp ' + i,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            ));
        }
        insert opps;

        List<IDP_Status_Event__e> events = new List<IDP_Status_Event__e>();
        for (Integer i = 0; i < opps.size(); i++) {
            events.add(new IDP_Status_Event__e(
                Opportunity_Id__c     = opps[i].Id,
                Content_Version_Id__c = '0684x000001Trg' + i + 'AAE',
                IDP_Status__c         = 'Failed',
                IDP_Error__c          = 'Bulk trigger error ' + i
            ));
        }

        Test.startTest();
        List<Database.SaveResult> results = EventBus.publish(events);
        Test.getEventBus().deliver();
        Test.stopTest();

        for (Database.SaveResult sr : results) {
            System.assert(sr.isSuccess(), 'Each platform event should publish successfully');
        }

        List<MuleSoft_Error_Log__c> logs = [SELECT Id FROM MuleSoft_Error_Log__c];
        System.assertEquals(3, logs.size());
    }
}