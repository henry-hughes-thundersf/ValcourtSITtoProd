@isTest
private class IDP_RFP_CalloutTest {

    private class IDP_RFP_HttpMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        public IDP_RFP_HttpMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(this.statusCode);
            response.setHeader('Content-Type', 'application/json');
            response.setBody(this.responseBody);
            return response;
        }
    }

    @isTest
    static void testSubmitRFPSuccess() {
        // Mock successful 200 response with correlationId
        String mockResponseBody = '{"correlationId": "CORR-12345-ABC"}';
        Test.setMock(HttpCalloutMock.class, new IDP_RFP_HttpMock(200, mockResponseBody));

        // Construct request
        IDP_RFP_Callout.Request req = new IDP_RFP_Callout.Request();
        req.opportunityId = '006000000000001AAA';
        req.contentVersionId = '068000000000001AAA';
        req.fileName = 'Sample_RFP.pdf';

        List<IDP_RFP_Callout.Request> requests = new List<IDP_RFP_Callout.Request>{ req };

        Test.startTest();
        List<IDP_RFP_Callout.Response> responses = IDP_RFP_Callout.submitRFP(requests);
        Test.stopTest();

        // Assertions
        System.assertEquals(1, responses.size(), 'Should return exactly one response.');
        IDP_RFP_Callout.Response res = responses[0];
        System.assertEquals(true, res.success, 'Success flag should be true.');
        System.assertEquals('CORR-12345-ABC', res.correlationId, 'Correlation ID should match mock payload.');
        System.assertEquals('RFP submitted successfully', res.message, 'Message should reflect successful submission.');
    }

    @isTest
    static void testSubmitRFPFailureStatusCode() {
        // Mock 500 error response
        String mockResponseBody = '{"error": "Internal Server Error"}';
        Test.setMock(HttpCalloutMock.class, new IDP_RFP_HttpMock(500, mockResponseBody));

        IDP_RFP_Callout.Request req = new IDP_RFP_Callout.Request();
        req.opportunityId = '006000000000001AAA';
        req.contentVersionId = '068000000000001AAA';
        req.fileName = 'Sample_RFP.pdf';

        List<IDP_RFP_Callout.Request> requests = new List<IDP_RFP_Callout.Request>{ req };

        Test.startTest();
        List<IDP_RFP_Callout.Response> responses = IDP_RFP_Callout.submitRFP(requests);
        Test.stopTest();

        // Assertions
        System.assertEquals(1, responses.size(), 'Should return exactly one response.');
        IDP_RFP_Callout.Response res = responses[0];
        System.assertEquals(false, res.success, 'Success flag should be false.');
        System.assert(res.message.contains('MuleSoft error: 500'), 'Error message should capture HTTP status code.');
    }

    @isTest
    static void testSubmitRFPException() {
        // Setting an empty list without proper mock configuration or forced failure scenario
        // Passing a request list containing a Null element forces a System.NullPointerException inside the loop
        List<IDP_RFP_Callout.Request> requests = new List<IDP_RFP_Callout.Request>{ null };

        Test.startTest();
        List<IDP_RFP_Callout.Response> responses = IDP_RFP_Callout.submitRFP(requests);
        Test.stopTest();

        // Assertions
        System.assertEquals(1, responses.size(), 'Should return one response block even on exception.');
        IDP_RFP_Callout.Response res = responses[0];
        System.assertEquals(false, res.success, 'Success flag should be false on exception.');
        System.assert(res.message.startsWith('Error:'), 'Message should begin with Exception prefix.');
    }
}