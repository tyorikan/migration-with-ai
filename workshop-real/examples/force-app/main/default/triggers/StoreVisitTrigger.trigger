/**
 * StoreVisitTrigger
 * StoreVisit__c オブジェクトのトリガー
 * ロジックは StoreVisitTriggerHandler に委譲する
 */
trigger StoreVisitTrigger on StoreVisit__c (
    after insert,
    after update,
    before delete
) {
    if (Trigger.isAfter && Trigger.isInsert) {
        StoreVisitTriggerHandler.onAfterInsert(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        StoreVisitTriggerHandler.onAfterUpdate(Trigger.new, Trigger.oldMap);
    }

    if (Trigger.isBefore && Trigger.isDelete) {
        StoreVisitTriggerHandler.onBeforeDelete(Trigger.old);
    }
}
