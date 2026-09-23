public class UpdateRecordInvocable {
    
    // Input class for Flow to allow multiple parameters
    public class RecordRequest {
        @InvocableVariable(label='JSON Array' required=true)
        public String jsonArray;
        
        @InvocableVariable(label='Record ID' required=false)
        public String recordID;
    }

    // Output class for Flow
    public class RecordResult {
        @InvocableVariable(label='Record Id to update')
        public Id recordIdToUpdate;
    }
    
    @InvocableMethod(label='Update Record' description='Updates existing record based on JSON parameter and record ID.')
    public static List<RecordResult> updateRecord (List<RecordRequest> requests) {
        
        List<SObject> recordsToUpdate = new List<SObject>();
        
        for(RecordRequest req : requests){
            String jsonStr = req.jsonArray;
            String currentRecordId = req.recordID; 
            Id realId = (Id)currentRecordId;
            Schema.SObjectType sobjectType = realId.getSObjectType(); 
                    
            if(String.isNotBlank(jsonStr)) {
                
                jsonStr = jsonStr.replace('json', '');
                jsonStr = jsonStr.replace('`', '');
                jsonStr = jsonStr.replace('\n', ' '); 
                System.debug('JSON: ' + jsonStr);
                
                Integer firstBrace = jsonStr.indexOf('[');
                Integer lastBrace = jsonStr.reverse().indexOf(']');

                String tempJson = jsonStr.mid(firstBrace, jsonStr.length() - lastBrace);
                System.debug('temp JSON: ' + tempJson);
                
                System.Type listType = System.Type.forName('List<' + sObjectType.getDescribe().getName() + '>');
                List<SObject> tempRecords = (List<SObject>)JSON.deserialize(tempJson, listType);
                
                for (SObject record : tempRecords) {
                    record.put('Id', realId);
                    recordsToUpdate.add(record);
                }
      
            }
        }      

        List<RecordResult> results = new List<RecordResult>();
        
        if(!recordsToUpdate.isEmpty()){
            try{
                update recordsToUpdate;
                
                //Populate output
               for (SObject sobj : recordsToUpdate) {
                    RecordResult ResultRec = new RecordResult();
                    ResultRec.recordIdToUpdate = sobj.Id;
                    results.add(ResultRec);
                }
                
            } catch(Exception ex){
                System.debug('Exception Occurred: ' + ex.getMessage());
            }
        }
        

        return results;
    }
}