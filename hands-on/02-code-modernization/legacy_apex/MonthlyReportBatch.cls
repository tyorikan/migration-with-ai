/**
 * MonthlyReportBatch.cls
 * 
 * 月末に実行され、当月の業務日報を集計して店舗ごとのサマリーレポートを生成する
 * Batch Apex クラス。
 * 
 * 集計内容:
 *   - 店舗ごとの訪問回数
 *   - 総カウンセリング時間
 *   - 評価別の件数分布（A/B/C/D）
 *   - フォローアップ未完了件数
 * 
 * ※ Cloud Run Jobs への変換対象（ワークショップ用サンプル）
 */
global class MonthlyReportBatch implements Database.Batchable<sObject>, Database.Stateful {

    private Date targetMonth;
    private Date monthStart;
    private Date monthEnd;

    // Stateful: バッチ全体で集計結果を保持
    global Map<Id, MonthlySummary> summaryMap = new Map<Id, MonthlySummary>();

    global MonthlyReportBatch() {
        this.targetMonth = Date.today().toStartOfMonth();
        this.monthStart = this.targetMonth;
        this.monthEnd = this.targetMonth.addMonths(1).addDays(-1);
    }

    global MonthlyReportBatch(Date targetMonth) {
        this.targetMonth = targetMonth;
        this.monthStart = targetMonth.toStartOfMonth();
        this.monthEnd = this.monthStart.addMonths(1).addDays(-1);
    }

    /**
     * start: 当月の承認済み日報を全件取得
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Account__c, Account__r.Name, Account__r.StoreCode__c,
                   ReportDate__c, OverallCondition__c,
                   (SELECT Id, DurationMinutes__c, FollowUpRequired__c,
                           FollowUpDate__c
                    FROM CounselingRecords__r)
            FROM DailyReport__c
            WHERE Status__c = '承認済'
              AND ReportDate__c >= :monthStart
              AND ReportDate__c <= :monthEnd
        ]);
    }

    /**
     * execute: 100件ずつ処理し、店舗ごとに集計
     */
    global void execute(Database.BatchableContext bc, List<DailyReport__c> reports) {
        for (DailyReport__c report : reports) {
            Id accountId = report.Account__c;

            MonthlySummary summary;
            if (summaryMap.containsKey(accountId)) {
                summary = summaryMap.get(accountId);
            } else {
                summary = new MonthlySummary();
                summary.accountId = accountId;
                summary.accountName = report.Account__r.Name;
                summary.storeCode = report.Account__r.StoreCode__c;
                summaryMap.put(accountId, summary);
            }

            // 訪問回数をインクリメント
            summary.visitCount++;

            // 評価分布をカウント
            String condition = report.OverallCondition__c;
            if (condition == 'A') summary.gradeA++;
            else if (condition == 'B') summary.gradeB++;
            else if (condition == 'C') summary.gradeC++;
            else if (condition == 'D') summary.gradeD++;

            // カウンセリング記録の集計
            if (report.CounselingRecords__r != null) {
                for (CounselingRecord__c cr : report.CounselingRecords__r) {
                    summary.totalCounselingMinutes += (cr.DurationMinutes__c != null)
                        ? cr.DurationMinutes__c.intValue() : 0;

                    if (cr.FollowUpRequired__c == true) {
                        summary.followUpTotal++;
                        if (cr.FollowUpDate__c != null && cr.FollowUpDate__c < Date.today()) {
                            summary.followUpOverdue++;
                        }
                    }
                }
            }
        }
    }

    /**
     * finish: 集計結果をログ出力（本番ではカスタムオブジェクトに保存）
     */
    global void finish(Database.BatchableContext bc) {
        System.debug('===== 月次サマリーレポート (' + monthStart.format() + ' ～ ' + monthEnd.format() + ') =====');

        for (MonthlySummary s : summaryMap.values()) {
            System.debug(String.format(
                '[{0}] {1}: 訪問{2}回, カウンセリング{3}分, 評価(A:{4}/B:{5}/C:{6}/D:{7}), フォロー(未完了:{8}/期限超過:{9})',
                new List<Object>{
                    s.storeCode, s.accountName, s.visitCount,
                    s.totalCounselingMinutes,
                    s.gradeA, s.gradeB, s.gradeC, s.gradeD,
                    s.followUpTotal, s.followUpOverdue
                }
            ));
        }

        System.debug('集計対象店舗数: ' + summaryMap.size());
    }

    /**
     * 月次サマリーのデータホルダー
     */
    global class MonthlySummary {
        public Id accountId;
        public String accountName;
        public String storeCode;
        public Integer visitCount = 0;
        public Integer gradeA = 0;
        public Integer gradeB = 0;
        public Integer gradeC = 0;
        public Integer gradeD = 0;
        public Integer totalCounselingMinutes = 0;
        public Integer followUpTotal = 0;
        public Integer followUpOverdue = 0;
    }
}
