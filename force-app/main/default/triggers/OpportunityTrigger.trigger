trigger OpportunityTrigger on Opportunity (before insert, before update, before delete, after insert, after update, after delete) {

    switch on Trigger.operationType {
        when BEFORE_INSERT{
            
        }
        when BEFORE_UPDATE{
            
        }
        when BEFORE_DELETE{

        }
        when AFTER_INSERT{

        }
        when AFTER_UPDATE{
            OpportunityTriggerHandler.handlerAfterUpdate(Trigger.newMap, Trigger.oldMap);
        }
        when AFTER_DELETE{

        }
    }
}