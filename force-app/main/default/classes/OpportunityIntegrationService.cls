public with sharing class OpportunityIntegrationService implements Queueable, Database.AllowsCallouts {
    private static final Integer CHUNK_SIZE = 100;
    private static final Integer MAX_LEN = 131072; // match your long text area length

    private Set<Id> opportunityIds;
    private Map<Id, String> previousStageMap;

    public OpportunityIntegrationService(Set<Id> opportunityIds, Map<Id, String> previousStageMap){
        this.opportunityIds = opportunityIds;
        this.previousStageMap = previousStageMap;
    }

    public void execute(QueueableContext qc){
        // Take up to 100 Ids for this job, the rest are chained to the next job
        Set<Id> chunkIds = new Set<Id>();
        Set<Id> remainingIds = new Set<Id>();
        for(Id oppId : opportunityIds){
            if(chunkIds.size() < CHUNK_SIZE){
                chunkIds.add(oppId);
            } else {
                remainingIds.add(oppId);
            }
        }

        // Only send records that are still Closed Won
        List<Opportunity> oppList = [SELECT Id, Name, Amount, StageName, AccountId, Account.Name, Account.Industry
                                     FROM Opportunity
                                     WHERE Id IN :chunkIds AND StageName = 'Closed Won'];

        if(!oppList.isEmpty()){
            sendOpportunities(oppList);
        }

        if(!remainingIds.isEmpty()){
            System.enqueueJob(new OpportunityIntegrationService(remainingIds, previousStageMap));
        }
    }

    private void sendOpportunities(List<Opportunity> oppList){
        Integration_Log__c log = new Integration_Log__c();
        log.Integration_Name__c = 'Opportunity Outbound API';
        log.Related_Record_Ids__c = String.join(new List<Id>(new Map<Id, Opportunity>(oppList).keySet()), ',');

        Boolean isSuccess = false;

        try {
            List<OpportunityPayloadDto> payloadsToSend = new List<OpportunityPayloadDto>();

            for(Opportunity opp : oppList){
                OpportunityPayloadDto oppWrapper = new OpportunityPayloadDto();
                oppWrapper.opportunityId = opp.Id;
                oppWrapper.opportunityName = opp.Name;
                oppWrapper.amount = opp.Amount;
                oppWrapper.stage = opp.StageName;

                if(opp.Account != null){
                    OpportunityPayloadDto.AccountData accWrapper = new OpportunityPayloadDto.AccountData();
                    accWrapper.accountId = opp.AccountId;
                    accWrapper.accountName = opp.Account.Name;
                    accWrapper.industry = opp.Account.Industry;
                    oppWrapper.account = accWrapper;
                }
                payloadsToSend.add(oppWrapper);
            }

            String jsonPayload = JSON.serialize(payloadsToSend);
            log.Request_Payload__c = jsonPayload.left(MAX_LEN);

            Http http = new Http();
            HttpRequest request = new HttpRequest();

            request.setEndpoint('callout:MyExternalSystemNamedCredential');
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json;charset=UTF-8');
            request.setTimeout(60000);
            request.setBody(jsonPayload);

            HttpResponse response = http.send(request);

            log.Http_Status_Code__c = response.getStatusCode();
            log.Response_Message__c = String.isBlank(response.getBody()) ? null : response.getBody().left(MAX_LEN);

            if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                System.debug('Integration Successful: ' + response.getStatus() + ' Code: ' + response.getStatusCode());
                log.Status__c = 'Success';
                isSuccess = true;
            } else {
                System.debug('Integration Failed. Status: ' + response.getStatus() + ' Code: ' + response.getStatusCode());
                log.Status__c = 'Failure';
            }

        } catch (Exception ex) {
            System.debug('Exception occurred during Integration: ' + ex.getMessage());
            log.Status__c = 'Failure';
            log.Response_Message__c = ('Exception Message: ' + ex.getMessage()).left(MAX_LEN);
        } finally {
            if (!isSuccess) {
                String revertIssues = revertStages(oppList);
                if (revertIssues != null) {
                    log.Response_Message__c = ((log.Response_Message__c == null ? '' : log.Response_Message__c)
                        + '\nRevert issues: ' + revertIssues).left(MAX_LEN);
                }
            }
            if (log.Request_Payload__c != null || log.Response_Message__c != null) {
                Database.insert(log, false);
            }
        }
    }

    // Puts the stage back to the previous value. Returns error text if any revert failed.
    private String revertStages(List<Opportunity> oppList){
        List<Opportunity> oppsToRevert = new List<Opportunity>();
        for(Opportunity opp : oppList){
            String previousStage = previousStageMap.get(opp.Id);
            if(previousStage != null){
                oppsToRevert.add(new Opportunity(Id = opp.Id, StageName = previousStage));
            }
        }

        List<String> errors = new List<String>();
        List<Database.SaveResult> results = Database.update(oppsToRevert, false);
        for(Integer i = 0; i < results.size(); i++){
            if(!results[i].isSuccess()){
                errors.add(oppsToRevert[i].Id + ': ' + results[i].getErrors()[0].getMessage());
            }
        }
        return errors.isEmpty() ? null : String.join(errors, '; ');
    }
}