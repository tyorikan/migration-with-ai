/**
 * DailyReportTrigger.trigger
 * 
 * 業務日報が「提出済」に更新された際に、以下を自動実行するトリガー:
 *   1. 店舗の最終訪問日を更新
 *   2. フォローアップが必要なカウンセリング記録の通知タスクを作成
 * 
 * ※ ワークショップ用サンプル。Pub/Sub + Cloud Run ワーカーへの変換対象。
 */
trigger DailyReportTrigger on DailyReport__c (after update) {

    List<Account> accountsToUpdate = new List<Account>();
    List<Task> tasksToCreate = new List<Task>();

    for (DailyReport__c newReport : Trigger.new) {
        DailyReport__c oldReport = Trigger.oldMap.get(newReport.Id);

        // ステータスが「提出済」に変わった場合のみ処理
        if (newReport.Status__c == '提出済' && oldReport.Status__c != '提出済') {

            // 1. 店舗の最終訪問日を更新
            Account acc = new Account(
                Id = newReport.Account__c
            );
            // カスタム項目: LastVisitDate__c に日報日付をセット
            // （本番ではこの項目が Account に存在する前提）
            acc.put('LastVisitDate__c', newReport.ReportDate__c);
            accountsToUpdate.add(acc);

            // 2. フォローアップが必要なカウンセリング記録を検索し、タスクを作成
            List<CounselingRecord__c> followUps = [
                SELECT Id, Contact__c, Contact__r.LastName,
                       Category__c, FollowUpDate__c, FollowUpNote__c
                FROM CounselingRecord__c
                WHERE DailyReport__c = :newReport.Id
                  AND FollowUpRequired__c = true
            ];

            for (CounselingRecord__c cr : followUps) {
                Task t = new Task();
                t.Subject = 'フォローアップ: ' + cr.Category__c + ' - ' + cr.Contact__r.LastName;
                t.Description = cr.FollowUpNote__c;
                t.OwnerId = newReport.Supervisor__c;
                t.WhoId = cr.Contact__c;
                t.WhatId = newReport.Id;
                t.ActivityDate = cr.FollowUpDate__c != null
                    ? cr.FollowUpDate__c
                    : Date.today().addDays(7);
                t.Priority = 'High';
                t.Status = 'Not Started';
                tasksToCreate.add(t);
            }
        }
    }

    if (!accountsToUpdate.isEmpty()) {
        try {
            update accountsToUpdate;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, '店舗の最終訪問日更新に失敗: ' + e.getMessage());
        }
    }

    if (!tasksToCreate.isEmpty()) {
        try {
            insert tasksToCreate;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'フォローアップタスクの作成に失敗: ' + e.getMessage());
        }
    }
}
