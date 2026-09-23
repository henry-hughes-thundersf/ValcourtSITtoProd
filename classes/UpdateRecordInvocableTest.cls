@IsTest
private class UpdateRecordInvocableTest {

    @IsTest
    static void testUpdateRecordSuccess() {
        // 1. Create test data
        Account testAcc = new Account(Name = 'Original Name', Phone = '12345');
        insert testAcc;

        // 2. Mock up the incoming payload containing markdown code blocks like your LLM output
        String mockJsonPayload = '```json\n' +
                                 '[\n' +
                                 '  {\n' +
                                 '    "Name": "Updated Account Name",\n' +
                                 '    "Phone": "98765"\n' +
                                 '  }\n' +
                                 ']\n' +
                                 '```';

        // 3. Construct the request object
        UpdateRecordInvocable.RecordRequest req = new UpdateRecordInvocable.RecordRequest();
        req.jsonArray = mockJsonPayload;
        req.recordID = testAcc.Id;

        List<UpdateRecordInvocable.RecordRequest> requests = new List<UpdateRecordInvocable.RecordRequest>{ req };

        // 4. Execute the Invocable Method
        Test.startTest();
        List<UpdateRecordInvocable.RecordResult> results = UpdateRecordInvocable.updateRecord(requests);
        Test.stopTest();

        // 5. Verify results and database updates
        Assert.isNotNull(results, 'Results list should not be null.');
        Assert.areEqual(1, results.size(), 'There should be exactly 1 result returned.');
        Assert.areEqual(testAcc.Id, results[0].recordIdToUpdate, 'Returned Record ID should match updated account ID.');

        Account updatedAcc = [SELECT Name, Phone FROM Account WHERE Id = :testAcc.Id];
        Assert.areEqual('Updated Account Name', updatedAcc.Name, 'Account Name should have been updated via the JSON payload.');
        Assert.areEqual('98765', updatedAcc.Phone, 'Account Phone should have been updated via the JSON payload.');
    }
}