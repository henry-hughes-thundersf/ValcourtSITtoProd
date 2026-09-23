/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : IDP_RFP_Callout
 * Author          : <YourName>
 * Created Date    : Jun 4, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 4, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 4, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class IDP_RFP_Callout {

    /**
     * Invocable method — called by Flow
     * Flow passes a list so we use List input/output
    */
    @InvocableMethod(
        label='Submit RFP to IDP'
        description='Sends the ContentVersion to MuleSoft IDP for processing'
    )
    public static List<Response> submitRFP(List<Request> requests) {

        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            Response res = new Response();
            try {
                Map<String, Object> body = new Map<String, Object>{
                    'opportunityId'    => req.opportunityId,
                    'contentVersionId' => req.contentVersionId,
                    'fileName'         => req.fileName
                };

                HttpRequest httpReq = new HttpRequest();
                httpReq.setEndpoint('callout:MuleSoft_IDP_API/api/v1/rfp-submissions');
                httpReq.setMethod('POST');
                httpReq.setHeader('Content-Type', 'application/json');
                httpReq.setBody(JSON.serialize(body));
                httpReq.setTimeout(120000);

                HttpResponse httpRes = new Http().send(httpReq);

                System.debug('Status: ' + httpRes.getStatusCode());
                System.debug('Body: ' + httpRes.getBody());

                if (httpRes.getStatusCode() == 200) {
                    Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(httpRes.getBody());

                    res.success  = true;
                    res.correlationId = (String) resp.get('correlationId');
                    res.message = 'RFP submitted successfully';
                } else {
                    res.success = false;
                    res.message = 'MuleSoft error: ' + httpRes.getStatusCode() + ' ' + httpRes.getBody();
                }
            } catch (Exception e) {
                res.success = false;
                res.message = 'Error: ' + e.getMessage();
            }
            responses.add(res);
        }

        return responses;
    }

    // ── Input wrapper ──────────────────────────────
    public class Request {
        @InvocableVariable(label='Opportunity Id' required=true)
        public String opportunityId;

        @InvocableVariable(label='Content Version Id' required=true)
        public String contentVersionId;

        @InvocableVariable(label='File Name' required=true)
        public String fileName;
    }

    // ── Output wrapper ─────────────────────────────
    public class Response {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Correlation Id')
        public String correlationId;

        @InvocableVariable(label='Message')
        public String message;
    }
}