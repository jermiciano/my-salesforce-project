@IsTest
public class OpportunityIntegrationServiceTest {

    // Fake external system that returns an error
    private class OpportunityIntegrationFailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"status":"error", "message":"Internal Server Error"}');
            response.setStatusCode(500);
            return response;
        }
    }

    // Fake external system that is unreachable (callout throws)
    private class OpportunityIntegrationExceptionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException('Connection timed out');
        }
    }

    // Committed before each test, so the bulk test can make a callout without
    // the "uncommitted work pending" error
    @TestSetup
    static void setupBulkData() {
        Account acc = new Account(Name = 'Bulk Account', Industry = 'Technology');
        insert acc;

        List<Opportunity> bulkOpps = new List<Opportunity>();
        for (Integer i = 0; i < 150; i++) {
            bulkOpps.add(new Opportunity(
                Name = 'Bulk Opp ' + i,
                AccountId = acc.Id,
                StageName = 'Closed Won',
                CloseDate = Date.today().addDays(30),
                Amount = 1000
            ));
        }
        insert bulkOpps;
    }

    private static Opportunity createProspectingOpportunity() {
        Account acc = new Account(Name = 'Test Cloud Account', Industry = 'Technology');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Integration Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 50000
        );
        insert opp;
        return opp;
    }

    // 1. Success: log is Success and the stage stays Closed Won
    @IsTest
    static void testOpportunitySuccessfulIntegration() {
        Opportunity opp = createProspectingOpportunity();

        Test.setMock(HttpCalloutMock.class, new OpportunityIntegrationMock());

        Test.startTest();
        opp.StageName = 'Closed Won';
        update opp;
        Test.stopTest(); // Forces the Queueable job to run completely within the test context

        List<Integration_Log__c> logs = [SELECT Status__c, Http_Status_Code__c FROM Integration_Log__c];
        System.assertEquals(1, logs.size(), 'An integration log record should have been generated.');
        System.assertEquals('Success', logs[0].Status__c, 'Log status should be marked as Success.');
        System.assertEquals(200, logs[0].Http_Status_Code__c, 'HTTP Status code should be 200.');

        System.assertEquals('Closed Won', [SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName,
            'Stage should stay Closed Won when the integration succeeds.');
    }

    // 2. Failure (HTTP 500): log is Failure and the stage is reverted
    @IsTest
    static void testOpportunityFailedIntegrationRevertsStage() {
        Opportunity opp = createProspectingOpportunity();

        Test.setMock(HttpCalloutMock.class, new OpportunityIntegrationFailMock());

        Test.startTest();
        opp.StageName = 'Closed Won';
        update opp;
        Test.stopTest();

        List<Integration_Log__c> logs = [SELECT Status__c, Http_Status_Code__c FROM Integration_Log__c];
        System.assertEquals(1, logs.size(), 'An integration log record should have been generated.');
        System.assertEquals('Failure', logs[0].Status__c, 'Log status should be marked as Failure.');
        System.assertEquals(500, logs[0].Http_Status_Code__c, 'HTTP Status code should be 500.');

        System.assertEquals('Prospecting', [SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName,
            'Stage should be reverted to the previous stage when the integration fails.');
    }

    // 3. Exception (callout throws): log is Failure and the stage is reverted
    @IsTest
    static void testOpportunityCalloutExceptionRevertsStage() {
        Opportunity opp = createProspectingOpportunity();

        Test.setMock(HttpCalloutMock.class, new OpportunityIntegrationExceptionMock());

        Test.startTest();
        opp.StageName = 'Closed Won';
        update opp;
        Test.stopTest();

        List<Integration_Log__c> logs = [SELECT Status__c, Http_Status_Code__c, Response_Message__c FROM Integration_Log__c];
        System.assertEquals(1, logs.size(), 'An integration log record should have been generated.');
        System.assertEquals('Failure', logs[0].Status__c, 'Log status should be marked as Failure.');
        System.assertEquals(null, logs[0].Http_Status_Code__c, 'No HTTP status code when the callout throws.');
        System.assert(logs[0].Response_Message__c.contains('Connection timed out'),
            'Log should contain the exception message.');

        System.assertEquals('Prospecting', [SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName,
            'Stage should be reverted when the callout throws an exception.');
    }

    // 4. No stage change to Closed Won: no job, no log
    @IsTest
    static void testNoIntegrationWhenStageIsNotClosedWon() {
        Opportunity opp = createProspectingOpportunity();

        Test.setMock(HttpCalloutMock.class, new OpportunityIntegrationMock());

        Test.startTest();
        opp.StageName = 'Negotiation/Review';
        update opp;
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Integration_Log__c],
            'No integration log should be created when the stage is not Closed Won.');
    }

    // 5. Bulk: 150 records are sent in 2 chunks (100 + 50) through chaining
    @IsTest
    static void testOpportunityBulkIntegrationChaining() {
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>([SELECT Id FROM Opportunity]);
        System.assertEquals(150, oppMap.size(), 'Test setup should contain 150 opportunities.');

        Map<Id, String> previousStageMap = new Map<Id, String>();
        for (Id oppId : oppMap.keySet()) {
            previousStageMap.put(oppId, 'Prospecting');
        }

        Test.setMock(HttpCalloutMock.class, new OpportunityIntegrationMock());

        Test.startTest();
        // Call execute directly: Salesforce does not allow a Queueable to chain
        // another Queueable inside a running test, so we start the first chunk
        // ourselves. The chained job (remaining 50) runs at Test.stopTest().
        new OpportunityIntegrationService(oppMap.keySet(), previousStageMap).execute(null);
        Test.stopTest();

        List<Integration_Log__c> logs = [SELECT Status__c FROM Integration_Log__c];
        System.assertEquals(2, logs.size(), '150 records should produce 2 logs (100 + 50).');
        for (Integration_Log__c log : logs) {
            System.assertEquals('Success', log.Status__c, 'Every chunk should be marked as Success.');
        }

        System.assertEquals(150, [SELECT COUNT() FROM Opportunity WHERE StageName = 'Closed Won'],
            'No stage should be reverted when every chunk succeeds.');
    }
}