/**
 * StoreVisitService
 * 店舗訪問記録のビジネスロジック層
 *
 * 主な責務:
 *   - 訪問記録の CRUD 操作（StoreVisitRepository を通じて）
 *   - ステータス遷移の制御
 *   - 訪問詳細（VisitDetail__c）の一括操作
 *   - ビジネスルールのバリデーション
 */
public with sharing class StoreVisitService {

    // ========== Custom Exceptions ==========

    public class BusinessException extends Exception {}
    public class NotFoundException extends Exception {}

    // ========== ステータス遷移ルール ==========

    private static final Map<String, Set<String>> VALID_TRANSITIONS = new Map<String, Set<String>>{
        'Draft'     => new Set<String>{ 'Submitted' },
        'Submitted' => new Set<String>{ 'Approved', 'Rejected' },
        'Rejected'  => new Set<String>{ 'Draft' },
        'Approved'  => new Set<String>()   // 終端状態
    };

    // ========== 一覧取得 ==========

    public static List<StoreVisit__c> getVisits(
        String status,
        String storeId,
        String fromDate,
        String toDate,
        Integer queryLimit,
        Integer queryOffset
    ) {
        String query = 'SELECT Id, Name, Store__c, Store__r.Name, Store__r.StoreCode__c, '
                     + 'VisitDate__c, Status__c, Purpose__c, Summary__c, NextAction__c, '
                     + 'Rating__c, Visitor__c, Visitor__r.Name, '
                     + 'CreatedDate, LastModifiedDate, '
                     + '(SELECT Id, Category__c, Description__c, DueDate__c, '
                     + 'IsCompleted__c, Priority__c FROM VisitDetails__r ORDER BY Priority__c) '
                     + 'FROM StoreVisit__c';

        List<String> conditions = new List<String>();

        if (String.isNotBlank(status)) {
            conditions.add('Status__c = :status');
        }
        if (String.isNotBlank(storeId)) {
            conditions.add('Store__c = :storeId');
        }
        if (String.isNotBlank(fromDate)) {
            Date parsedFromDate = Date.valueOf(fromDate);
            conditions.add('VisitDate__c >= :parsedFromDate');
        }
        if (String.isNotBlank(toDate)) {
            Date parsedToDate = Date.valueOf(toDate);
            conditions.add('VisitDate__c <= :parsedToDate');
        }

        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }

        query += ' ORDER BY VisitDate__c DESC';
        query += ' LIMIT :queryLimit OFFSET :queryOffset';

        return Database.query(query);
    }

    // ========== 詳細取得 ==========

    public static StoreVisit__c getVisitById(String visitId) {
        List<StoreVisit__c> visits = [
            SELECT Id, Name, Store__c, Store__r.Name, Store__r.StoreCode__c,
                   Store__r.Region__c, Store__r.Address__c, Store__r.Phone__c,
                   VisitDate__c, Status__c, Purpose__c, Summary__c, NextAction__c,
                   Rating__c, Visitor__c, Visitor__r.Name, Visitor__r.Email,
                   CreatedDate, LastModifiedDate,
                   (SELECT Id, Category__c, Description__c, DueDate__c,
                    IsCompleted__c, Priority__c, CreatedDate
                    FROM VisitDetails__r ORDER BY Priority__c ASC)
            FROM StoreVisit__c
            WHERE Id = :visitId
            LIMIT 1
        ];

        return visits.isEmpty() ? null : visits[0];
    }

    // ========== 新規作成 ==========

    public static StoreVisit__c createVisit(Map<String, Object> requestBody) {
        // 店舗の存在確認
        String storeId = (String) requestBody.get('storeId');
        List<Store__c> stores = [SELECT Id FROM Store__c WHERE Id = :storeId LIMIT 1];
        if (stores.isEmpty()) {
            throw new BusinessException('指定された店舗が見つかりません: ' + storeId);
        }

        // 同一日・同一店舗の重複チェック
        Date visitDate = Date.valueOf((String) requestBody.get('visitDate'));
        List<StoreVisit__c> duplicates = [
            SELECT Id FROM StoreVisit__c
            WHERE Store__c = :storeId
            AND VisitDate__c = :visitDate
            AND Visitor__c = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (!duplicates.isEmpty()) {
            throw new BusinessException('同一日・同一店舗の訪問記録が既に存在します');
        }

        // レコード作成
        StoreVisit__c visit = new StoreVisit__c();
        visit.Store__c = storeId;
        visit.VisitDate__c = visitDate;
        visit.Purpose__c = (String) requestBody.get('purpose');
        visit.Summary__c = (String) requestBody.get('summary');
        visit.NextAction__c = (String) requestBody.get('nextAction');
        visit.Status__c = 'Draft';
        visit.Visitor__c = UserInfo.getUserId();

        if (requestBody.containsKey('rating')) {
            visit.Rating__c = Decimal.valueOf(String.valueOf(requestBody.get('rating')));
        }

        // トランザクション: 親子レコードを一括作成
        Savepoint sp = Database.setSavepoint();
        try {
            insert visit;

            // 訪問詳細の一括作成
            if (requestBody.containsKey('details')) {
                List<Object> detailList = (List<Object>) requestBody.get('details');
                List<VisitDetail__c> details = new List<VisitDetail__c>();

                for (Object detailObj : detailList) {
                    Map<String, Object> detailMap = (Map<String, Object>) detailObj;
                    VisitDetail__c detail = new VisitDetail__c();
                    detail.StoreVisit__c = visit.Id;
                    detail.Category__c = (String) detailMap.get('category');
                    detail.Description__c = (String) detailMap.get('description');
                    detail.Priority__c = detailMap.containsKey('priority')
                        ? Decimal.valueOf(String.valueOf(detailMap.get('priority')))
                        : 3;
                    detail.IsCompleted__c = false;

                    if (detailMap.containsKey('dueDate')) {
                        detail.DueDate__c = Date.valueOf((String) detailMap.get('dueDate'));
                    }

                    details.add(detail);
                }

                if (!details.isEmpty()) {
                    insert details;
                }
            }
        } catch (Exception e) {
            Database.rollback(sp);
            throw e;
        }

        // 作成後のデータを返却（リレーション含む）
        return getVisitById(visit.Id);
    }

    // ========== 更新 ==========

    public static StoreVisit__c updateVisit(String visitId, Map<String, Object> requestBody) {
        StoreVisit__c existing = getVisitById(visitId);
        if (existing == null) {
            throw new NotFoundException('指定された訪問記録が見つかりません: ' + visitId);
        }

        // ステータス遷移のバリデーション
        if (requestBody.containsKey('status')) {
            String newStatus = (String) requestBody.get('status');
            validateStatusTransition(existing.Status__c, newStatus);
            existing.Status__c = newStatus;
        }

        // Approved 済みの場合、ステータス以外の変更は不可
        if (existing.Status__c == 'Approved' && !requestBody.containsKey('status')) {
            throw new BusinessException('承認済みの訪問記録は編集できません');
        }

        // フィールド更新
        if (requestBody.containsKey('purpose')) {
            existing.Purpose__c = (String) requestBody.get('purpose');
        }
        if (requestBody.containsKey('summary')) {
            existing.Summary__c = (String) requestBody.get('summary');
        }
        if (requestBody.containsKey('nextAction')) {
            existing.NextAction__c = (String) requestBody.get('nextAction');
        }
        if (requestBody.containsKey('rating')) {
            existing.Rating__c = Decimal.valueOf(String.valueOf(requestBody.get('rating')));
        }
        if (requestBody.containsKey('visitDate')) {
            existing.VisitDate__c = Date.valueOf((String) requestBody.get('visitDate'));
        }

        update existing;

        return getVisitById(existing.Id);
    }

    // ========== 削除 ==========

    public static void deleteVisit(String visitId) {
        StoreVisit__c existing = getVisitById(visitId);
        if (existing == null) {
            throw new NotFoundException('指定された訪問記録が見つかりません: ' + visitId);
        }

        // Draft のみ削除可能
        if (existing.Status__c != 'Draft') {
            throw new BusinessException(
                '下書き（Draft）ステータスの訪問記録のみ削除可能です。'
                + '現在のステータス: ' + existing.Status__c
            );
        }

        // 子レコード（VisitDetail__c）は Master-Detail のため CASCADE 削除される
        delete existing;
    }

    // ========== Private Methods ==========

    private static void validateStatusTransition(String currentStatus, String newStatus) {
        Set<String> allowedTransitions = VALID_TRANSITIONS.get(currentStatus);
        if (allowedTransitions == null || !allowedTransitions.contains(newStatus)) {
            throw new BusinessException(
                'ステータス遷移が不正です: ' + currentStatus + ' → ' + newStatus
                + '。許可された遷移先: ' + (allowedTransitions != null ? String.join(new List<String>(allowedTransitions), ', ') : 'なし')
            );
        }
    }
}
