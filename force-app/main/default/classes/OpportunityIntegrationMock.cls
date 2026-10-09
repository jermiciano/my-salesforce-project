@IsTest
public class OpportunityIntegrationMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
        HttpResponse response = new HttpResponse();
        response.setHeader('Content-Type', 'application/json');
        response.setBody('{"status":"success", "message":"Received"}');
        response.setStatusCode(200);
        return response;
    }
}