/**
 * StoreVisitTriggerHandler
 * StoreVisit__c トリガーのハンドラークラス
 *
 * 副作用:
 *   - 訪問記録が Submitted になった時、店舗マスタの最終訪問日を更新
 *   - 訪問記録が Approved になった時、訪問者に通知メールを送信
 *   - 訪問記録の Rating が変更された時、店舗マスタの平均評価を再計算
 */
public with sharing class StoreVisitTriggerHandler {

    // ========== Trigger Entry Points ==========

    public static void onAfterUpdate(
        List<StoreVisit__c> newList,
        Map<Id, StoreVisit__c> oldMap
    ) {
        List<StoreVisit__c> submittedVisits = new List<StoreVisit__c>();
        List<StoreVisit__c> approvedVisits = new List<StoreVisit__c>();
        Set<Id> storeIdsForRatingUpdate = new Set<Id>();

        for (StoreVisit__c visit : newList) {
            StoreVisit__c oldVisit = oldMap.get(visit.Id);

            // ステータスが Draft → Submitted に変わった場合
            if (visit.Status__c == 'Submitted' && oldVisit.Status__c == 'Draft') {
                submittedVisits.add(visit);
            }

            // ステータスが Submitted → Approved に変わった場合
            if (visit.Status__c == 'Approved' && oldVisit.Status__c == 'Submitted') {
                approvedVisits.add(visit);
            }

            // Rating が変更された場合
            if (visit.Rating__c != oldVisit.Rating__c) {
                storeIdsForRatingUpdate.add(visit.Store__c);
            }
        }

        // 最終訪問日の更新
        if (!submittedVisits.isEmpty()) {
            updateLastVisitDate(submittedVisits);
        }

        // 承認通知メールの送信
        if (!approvedVisits.isEmpty()) {
            sendApprovalNotification(approvedVisits);
        }

        // 平均評価の再計算
        if (!storeIdsForRatingUpdate.isEmpty()) {
            recalculateAverageRating(storeIdsForRatingUpdate);
        }
    }

    public static void onAfterInsert(List<StoreVisit__c> newList) {
        // 新規作成時は特に副作用なし（Draft で作成されるため）
    }

    public static void onBeforeDelete(List<StoreVisit__c> oldList) {
        // 削除前バリデーション: Draft 以外は削除不可
        for (StoreVisit__c visit : oldList) {
            if (visit.Status__c != 'Draft') {
                visit.addError(
                    '下書き（Draft）ステータスの訪問記録のみ削除可能です。'
                    + '現在のステータス: ' + visit.Status__c
                );
            }
        }
    }

    // ========== Private Methods ==========

    /**
     * 店舗マスタの最終訪問日を更新
     */
    private static void updateLastVisitDate(List<StoreVisit__c> visits) {
        Map<Id, Date> storeLatestVisitMap = new Map<Id, Date>();

        for (StoreVisit__c visit : visits) {
            Id storeId = visit.Store__c;
            if (!storeLatestVisitMap.containsKey(storeId)
                || visit.VisitDate__c > storeLatestVisitMap.get(storeId)) {
                storeLatestVisitMap.put(storeId, visit.VisitDate__c);
            }
        }

        List<Store__c> storesToUpdate = new List<Store__c>();
        for (Id storeId : storeLatestVisitMap.keySet()) {
            storesToUpdate.add(new Store__c(
                Id = storeId,
                LastVisitDate__c = storeLatestVisitMap.get(storeId)
            ));
        }

        if (!storesToUpdate.isEmpty()) {
            update storesToUpdate;
        }
    }

    /**
     * 承認通知メールの送信
     */
    private static void sendApprovalNotification(List<StoreVisit__c> visits) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        // 訪問者情報を取得
        Set<Id> visitorIds = new Set<Id>();
        for (StoreVisit__c visit : visits) {
            visitorIds.add(visit.Visitor__c);
        }
        Map<Id, User> visitors = new Map<Id, User>(
            [SELECT Id, Email, Name FROM User WHERE Id IN :visitorIds]
        );

        for (StoreVisit__c visit : visits) {
            User visitor = visitors.get(visit.Visitor__c);
            if (visitor != null && String.isNotBlank(visitor.Email)) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>{ visitor.Email });
                email.setSubject('【店舗訪問記録】承認されました: ' + visit.Name);
                email.setPlainTextBody(
                    visitor.Name + ' 様\n\n'
                    + '以下の訪問記録が承認されました。\n\n'
                    + '訪問記録番号: ' + visit.Name + '\n'
                    + '訪問日: ' + String.valueOf(visit.VisitDate__c) + '\n'
                    + '店舗: ' + visit.Store__c + '\n\n'
                    + 'ご確認ください。'
                );
                emails.add(email);
            }
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }
    }

    /**
     * 店舗の平均評価を再計算
     */
    private static void recalculateAverageRating(Set<Id> storeIds) {
        List<AggregateResult> results = [
            SELECT Store__c, AVG(Rating__c) avgRating
            FROM StoreVisit__c
            WHERE Store__c IN :storeIds
            AND Rating__c != null
            AND Status__c IN ('Submitted', 'Approved')
            GROUP BY Store__c
        ];

        List<Store__c> storesToUpdate = new List<Store__c>();
        for (AggregateResult ar : results) {
            storesToUpdate.add(new Store__c(
                Id = (Id) ar.get('Store__c'),
                AverageRating__c = (Decimal) ar.get('avgRating')
            ));
        }

        if (!storesToUpdate.isEmpty()) {
            update storesToUpdate;
        }
    }
}
