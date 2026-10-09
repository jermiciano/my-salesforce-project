public with sharing class OpportunityTriggerHandler {
   public static void handlerAfterUpdate(Map<Id, Opportunity> newMap, Map<Id, Opportunity> oldMap){
        Set<Id> oppIdsToSend = new Set<Id>();
        Map<Id, String> previousStageMap = new Map<Id, String>(); // used to revert the stage on failure

        for(Opportunity newOpp : newMap.Values()){
            Opportunity oldOpp = oldMap.get(newOpp.Id);

            if(newOpp.StageName == 'Closed Won' && oldOpp.StageName != 'Closed Won'){
                oppIdsToSend.add(newOpp.Id);
                previousStageMap.put(newOpp.Id, oldOpp.StageName);
            }
        }
        if(!oppIdsToSend.isEmpty()){
            try {
                OpportunityIntegrationService queueableJob = new OpportunityIntegrationService(oppIdsToSend, previousStageMap);

                System.enqueueJob(queueableJob);
            } catch (Exception ex) {
                // Could not enqueue (e.g. job limit). Block the save with a visible error.
                for(Id oppId : oppIdsToSend){
                    newMap.get(oppId).addError('Unable to start the integration. Please try again later.');
                }
            }
        }
    }
}