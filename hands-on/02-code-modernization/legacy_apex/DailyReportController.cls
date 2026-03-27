/**
 * DailyReportController.cls
 * 
 * 業務日報の CRUD 操作を提供する Apex REST コントローラー。
 * スーパーバイザーがフランチャイズ店舗を訪問した際の日報を管理する。
 * 
 * ※ このクラスはワークショップ用のサンプルです。
 *    典型的なレガシー Apex の特徴（ロジック混在、直接 DML、try-catch）を意図的に含んでいます。
 */
@RestResource(urlMapping='/api/daily-reports/*')
global with sharing class DailyReportController {

    /**
     * 日報一覧の取得（検索条件付き）
     */
    @HttpGet
    global static List<DailyReport__c> getReports() {
        RestRequest req = RestContext.request;
        String status = req.params.get('status');
        String region = req.params.get('region');
        String dateFrom = req.params.get('dateFrom');
        String dateTo = req.params.get('dateTo');

        String query = 'SELECT Id, Name, ReportDate__c, Supervisor__c, '
            + 'Account__c, Account__r.Name, Account__r.StoreCode__c, Account__r.Region__c, '
            + 'VisitStartTime__c, VisitEndTime__c, VisitPurpose__c, '
            + 'OverallCondition__c, Summary__c, NextAction__c, Status__c, '
            + 'ApprovedBy__c, ApprovedDate__c, '
            + '(SELECT Id, Name, Contact__c, Contact__r.LastName, Category__c, '
            + '  Detail__c, DurationMinutes__c, FollowUpRequired__c, FollowUpDate__c '
            + '  FROM CounselingRecords__r) '
            + 'FROM DailyReport__c';

        List<String> conditions = new List<String>();
        if (String.isNotBlank(status)) {
            conditions.add('Status__c = :status');
        }
        if (String.isNotBlank(region)) {
            conditions.add('Account__r.Region__c = :region');
        }
        if (String.isNotBlank(dateFrom)) {
            Date df = Date.valueOf(dateFrom);
            conditions.add('ReportDate__c >= :df');
        }
        if (String.isNotBlank(dateTo)) {
            Date dt = Date.valueOf(dateTo);
            conditions.add('ReportDate__c <= :dt');
        }

        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }
        query += ' ORDER BY ReportDate__c DESC LIMIT 200';

        return Database.query(query);
    }

    /**
     * 日報の新規作成（カウンセリング記録含む）
     */
    @HttpPost
    global static DailyReport__c createReport() {
        RestRequest req = RestContext.request;
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());

        try {
            // 1. 日報レコードの作成
            DailyReport__c report = new DailyReport__c();
            report.ReportDate__c = Date.valueOf((String) body.get('reportDate'));
            report.Supervisor__c = UserInfo.getUserId();
            report.Account__c = (String) body.get('accountId');
            report.VisitStartTime__c = DateTime.valueOf((String) body.get('visitStartTime'));
            report.VisitEndTime__c = DateTime.valueOf((String) body.get('visitEndTime'));
            report.VisitPurpose__c = (String) body.get('visitPurpose');
            report.OverallCondition__c = (String) body.get('overallCondition');
            report.Summary__c = (String) body.get('summary');
            report.NextAction__c = (String) body.get('nextAction');
            report.Status__c = '下書き';

            insert report;

            // 2. カウンセリング記録の一括作成
            List<Object> counselings = (List<Object>) body.get('counselingRecords');
            if (counselings != null && !counselings.isEmpty()) {
                List<CounselingRecord__c> records = new List<CounselingRecord__c>();
                for (Object c : counselings) {
                    Map<String, Object> cMap = (Map<String, Object>) c;
                    CounselingRecord__c cr = new CounselingRecord__c();
                    cr.DailyReport__c = report.Id;
                    cr.Contact__c = (String) cMap.get('contactId');
                    cr.Category__c = (String) cMap.get('category');
                    cr.Detail__c = (String) cMap.get('detail');
                    cr.DurationMinutes__c = (Decimal) cMap.get('durationMinutes');
                    cr.FollowUpRequired__c = cMap.get('followUpRequired') == true;
                    if (cMap.get('followUpDate') != null) {
                        cr.FollowUpDate__c = Date.valueOf((String) cMap.get('followUpDate'));
                    }
                    cr.FollowUpNote__c = (String) cMap.get('followUpNote');
                    records.add(cr);
                }
                insert records;
            }

            return report;
        } catch (DmlException e) {
            RestContext.response.statusCode = 400;
            throw new RestException('日報の作成に失敗しました: ' + e.getMessage());
        } catch (Exception e) {
            RestContext.response.statusCode = 500;
            throw new RestException('予期しないエラーが発生しました: ' + e.getMessage());
        }
    }

    /**
     * 日報のステータス更新（提出・承認・差戻し）
     */
    @HttpPatch
    global static DailyReport__c updateReportStatus() {
        RestRequest req = RestContext.request;
        String reportId = req.requestURI.substring(req.requestURI.lastIndexOf('/') + 1);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());

        String newStatus = (String) body.get('status');

        try {
            DailyReport__c report = [
                SELECT Id, Status__c, Supervisor__c
                FROM DailyReport__c
                WHERE Id = :reportId
                LIMIT 1
            ];

            // ステータス遷移のバリデーション
            if (newStatus == '提出済' && report.Status__c != '下書き' && report.Status__c != '差戻し') {
                throw new RestException('下書きまたは差戻しの日報のみ提出できます。');
            }
            if (newStatus == '承認済') {
                report.ApprovedBy__c = UserInfo.getUserId();
                report.ApprovedDate__c = DateTime.now();
            }

            report.Status__c = newStatus;
            update report;

            return report;
        } catch (QueryException e) {
            RestContext.response.statusCode = 404;
            throw new RestException('指定された日報が見つかりません。');
        } catch (Exception e) {
            RestContext.response.statusCode = 500;
            throw new RestException('ステータス更新に失敗しました: ' + e.getMessage());
        }
    }

    /**
     * 日報の削除（下書きのみ）
     */
    @HttpDelete
    global static void deleteReport() {
        RestRequest req = RestContext.request;
        String reportId = req.requestURI.substring(req.requestURI.lastIndexOf('/') + 1);

        try {
            DailyReport__c report = [
                SELECT Id, Status__c
                FROM DailyReport__c
                WHERE Id = :reportId
                LIMIT 1
            ];

            if (report.Status__c != '下書き') {
                RestContext.response.statusCode = 400;
                throw new RestException('下書きステータスの日報のみ削除できます。');
            }

            // Master-Detail により CounselingRecord__c も CASCADE 削除される
            delete report;
            RestContext.response.statusCode = 204;
        } catch (QueryException e) {
            RestContext.response.statusCode = 404;
            throw new RestException('指定された日報が見つかりません。');
        }
    }

    public class RestException extends Exception {}
}
