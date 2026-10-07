public with sharing class OpportunityTriggerHandler {
    public static void handlerAfterUpdate(Map<Id, Opportunity> newMap, Map<Id, Opportunity> oldMap){
        Set<Id> oppIdsToSend = new Set<Id>();

        for(Opportunity newOpp : newMap.Values()){
            Opportunity oldOpp = oldMap.get(newOpp.Id);

            if(newOpp.StageName == 'Closed Won' && oldOpp.StageName != 'Closed Won'){
                oppIdsToSend.add(newOpp.Id);
            }
        }
        if(!oppIdsToSend.isEmpty()){
            OpportunityIntegrationService.sendOpportunitiesToExternalSystem(oppIdsToSend);
        }
    }
}