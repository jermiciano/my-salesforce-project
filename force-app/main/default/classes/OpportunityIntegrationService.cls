public with sharing class OpportunityIntegrationService {
    @future(callout=true)
    public static void sendOpportunitiesToExternalSystem(Set<Id> opportunityIds){
        Integration_Log__c log = new Integration_Log__c();
        log.Integration_Name__c = 'Opportunity Outbound API';
        try {
            List<Opportunity> oppList = [SELECT Id, Name, Amount, StageName, Account.Name, Account.Industry
            FROM Opportunity
            WHERE Id IN :opportunityIds];

            if(oppList.isEmpty()) return;

            List<OpportunityPayloadDto> payloadsToSend = new List<OpportunityPayloadDto>();

            for(Opportunity opp : oppList){
                OpportunityPayloadDto oppWrapper = new OpportunityPayloadDto();
                oppWrapper.opportunityId = opp.Id;
                oppWrapper.opportunityName = opp.Name;
                oppWrapper.amount = opp.Amount;
                oppWrapper.stage = opp.StageName;

                if(opp.Account != null){
                    OpportunityPayloadDto.AccountData accWrapper = new OpportunityPayloadDto();
                    accWrapper.accountId = opp.AccountId;
                    accWrapper.accountName = opp.Account.Name;
                    accwrapper.industry = opp.Account.Industry;
                    oppWrapper.account = accWrapper;
                }

                payloadsToSend.add(oppWrapper);
            }

            String jsonPayload = JSON.serialize(payloadsToSend);
            log.Request_Payload__c = jsonPayload;

            Http http = new Http();
            HttpRequest request = new HttpRequest();

            reuqest.setEndpoint('callout:MyExternalSystemNamedCredential');
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json;charset=UTF-8');
            request.setBody(jsonPayload);

            HttpResponse response = htt.send(request);

            log.Http_Status_Code__c = response.getStatusCode();
            log.Response_Message__c = response.getBody();

            if(response.getStatusCode() == 200 || response.getStatusCode() == 201){
                System.debug('Integration Successful: ' + response.getStatus() + 'Code: ' + response.getStatusCode());
                log.Status__c = 'Success';
            } else {
                System.debug('Integration Failed. Status: ' + response.getStatus() + 'Code: ' + response.getStatusCode());
                log.Status__c = 'Failure';
            }
        } catch (Exception ex) {
            System.debug('Excemption occured during Integration: ' + ex.getMessage());
            log.Status__c = 'Failure';
            log.Response_Message__c = 'Exception Message: ' + ex.getMessage();
        } finally {
            if(log.Request_Payload__c != null || log.Response_Message__c != null){
                insert log;
            }
        }
    }
}