/**
 * StoreVisitMonthlyBatch
 * 月次集計バッチ
 *
 * 実行スケジュール: 毎月1日 AM 2:00
 * 処理内容:
 *   - 前月の訪問記録を集計
 *   - 店舗ごとの訪問回数、平均評価、未完了アクション数を算出
 *   - 集計結果を MonthlyVisitSummary__c に保存
 *   - 管理者にサマリーメールを送信
 */
public class StoreVisitMonthlyBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Date targetMonthStart;
    private Date targetMonthEnd;
    private Integer totalStoresProcessed = 0;
    private Integer totalVisitsProcessed = 0;
    private List<String> errors = new List<String>();

    public StoreVisitMonthlyBatch() {
        // デフォルト: 前月
        this.targetMonthStart = Date.today().toStartOfMonth().addMonths(-1);
        this.targetMonthEnd = Date.today().toStartOfMonth().addDays(-1);
    }

    public StoreVisitMonthlyBatch(Date monthStart, Date monthEnd) {
        this.targetMonthStart = monthStart;
        this.targetMonthEnd = monthEnd;
    }

    // ========== Batchable Interface ==========

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, StoreCode__c, Region__c
            FROM Store__c
            WHERE IsActive__c = true
            ORDER BY Region__c, StoreCode__c
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Store__c> stores) {
        Set<Id> storeIds = new Set<Id>();
        for (Store__c store : stores) {
            storeIds.add(store.Id);
        }

        // 対象月の訪問記録を取得
        List<AggregateResult> visitStats = [
            SELECT Store__c,
                   COUNT(Id) visitCount,
                   AVG(Rating__c) avgRating,
                   MIN(Rating__c) minRating,
                   MAX(Rating__c) maxRating
            FROM StoreVisit__c
            WHERE Store__c IN :storeIds
            AND VisitDate__c >= :targetMonthStart
            AND VisitDate__c <= :targetMonthEnd
            AND Status__c IN ('Submitted', 'Approved')
            GROUP BY Store__c
        ];

        Map<Id, AggregateResult> statsMap = new Map<Id, AggregateResult>();
        for (AggregateResult ar : visitStats) {
            statsMap.put((Id) ar.get('Store__c'), ar);
        }

        // 未完了アクションを取得
        List<AggregateResult> pendingActions = [
            SELECT StoreVisit__r.Store__c storeId,
                   COUNT(Id) pendingCount
            FROM VisitDetail__c
            WHERE StoreVisit__r.Store__c IN :storeIds
            AND IsCompleted__c = false
            AND DueDate__c <= :targetMonthEnd
            GROUP BY StoreVisit__r.Store__c
        ];

        Map<Id, Integer> pendingMap = new Map<Id, Integer>();
        for (AggregateResult ar : pendingActions) {
            pendingMap.put((Id) ar.get('storeId'), (Integer) ar.get('pendingCount'));
        }

        // サマリーレコード作成
        List<MonthlyVisitSummary__c> summaries = new List<MonthlyVisitSummary__c>();
        for (Store__c store : stores) {
            MonthlyVisitSummary__c summary = new MonthlyVisitSummary__c();
            summary.Store__c = store.Id;
            summary.MonthStart__c = targetMonthStart;
            summary.MonthEnd__c = targetMonthEnd;

            AggregateResult stats = statsMap.get(store.Id);
            if (stats != null) {
                summary.VisitCount__c = (Integer) stats.get('visitCount');
                summary.AverageRating__c = (Decimal) stats.get('avgRating');
                summary.MinRating__c = (Decimal) stats.get('minRating');
                summary.MaxRating__c = (Decimal) stats.get('maxRating');
            } else {
                summary.VisitCount__c = 0;
                summary.AverageRating__c = null;
            }

            summary.PendingActionCount__c = pendingMap.containsKey(store.Id)
                ? pendingMap.get(store.Id) : 0;

            summaries.add(summary);
            totalStoresProcessed++;
            totalVisitsProcessed += (Integer)(summary.VisitCount__c != null ? summary.VisitCount__c : 0);
        }

        try {
            upsert summaries;
        } catch (DmlException e) {
            errors.add('DML Error: ' + e.getMessage());
        }
    }

    public void finish(Database.BatchableContext bc) {
        // 管理者にサマリーメールを送信
        String adminEmail = [
            SELECT Email FROM User
            WHERE Profile.Name = 'System Administrator'
            AND IsActive = true
            LIMIT 1
        ].Email;

        if (String.isNotBlank(adminEmail)) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ adminEmail });
            email.setSubject('【月次集計完了】店舗訪問記録 '
                + targetMonthStart.format() + ' 〜 ' + targetMonthEnd.format());

            String body = '月次集計バッチが完了しました。\n\n'
                + '対象期間: ' + targetMonthStart.format() + ' 〜 ' + targetMonthEnd.format() + '\n'
                + '処理店舗数: ' + totalStoresProcessed + '\n'
                + '処理訪問数: ' + totalVisitsProcessed + '\n';

            if (!errors.isEmpty()) {
                body += '\n⚠️ エラー:\n' + String.join(errors, '\n');
            }

            email.setPlainTextBody(body);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email }, false);
        }
    }
}
