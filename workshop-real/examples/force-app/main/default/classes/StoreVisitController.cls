/**
 * StoreVisitController
 * 店舗訪問記録の REST API コントローラー
 * 
 * エンドポイント:
 *   GET    /services/apexrest/store-visits          - 訪問記録一覧取得（フィルタ可）
 *   GET    /services/apexrest/store-visits/{id}     - 訪問記録詳細取得
 *   POST   /services/apexrest/store-visits          - 訪問記録新規作成
 *   PATCH  /services/apexrest/store-visits/{id}     - 訪問記録更新
 *   DELETE /services/apexrest/store-visits/{id}     - 訪問記録削除
 */
@RestResource(urlMapping='/store-visits/*')
global with sharing class StoreVisitController {

    /**
     * 訪問記録一覧取得
     * クエリパラメータ:
     *   status   - ステータスでフィルタ（Draft/Submitted/Approved/Rejected）
     *   storeId  - 店舗IDでフィルタ
     *   fromDate - 開始日でフィルタ（YYYY-MM-DD）
     *   toDate   - 終了日でフィルタ（YYYY-MM-DD）
     *   limit    - 取得件数上限（デフォルト50、最大200）
     *   offset   - オフセット（ページング用）
     */
    @HttpGet
    global static void getVisits() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            // URLパスからIDを取得（/store-visits/{id} の場合）
            String visitId = req.requestURI.substringAfterLast('/');
            if (String.isNotBlank(visitId) && visitId != 'store-visits') {
                // 詳細取得
                StoreVisit__c visit = StoreVisitService.getVisitById(visitId);
                if (visit == null) {
                    res.statusCode = 404;
                    res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                        'error' => '指定された訪問記録が見つかりません',
                        'code' => 'VISIT_NOT_FOUND'
                    }));
                    return;
                }
                res.statusCode = 200;
                res.responseBody = Blob.valueOf(JSON.serialize(visit));
                return;
            }

            // 一覧取得
            String status = req.params.get('status');
            String storeId = req.params.get('storeId');
            String fromDate = req.params.get('fromDate');
            String toDate = req.params.get('toDate');
            Integer queryLimit = 50;
            Integer queryOffset = 0;

            if (req.params.containsKey('limit')) {
                queryLimit = Math.min(Integer.valueOf(req.params.get('limit')), 200);
            }
            if (req.params.containsKey('offset')) {
                queryOffset = Integer.valueOf(req.params.get('offset'));
            }

            List<StoreVisit__c> visits = StoreVisitService.getVisits(
                status, storeId, fromDate, toDate, queryLimit, queryOffset
            );

            Map<String, Object> response = new Map<String, Object>{
                'data' => visits,
                'count' => visits.size(),
                'limit' => queryLimit,
                'offset' => queryOffset
            };

            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(response));

        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'error' => e.getMessage(),
                'code' => 'INTERNAL_ERROR'
            }));
        }
    }

    /**
     * 訪問記録新規作成
     * リクエストボディ:
     *   storeId     - 店舗ID（必須）
     *   visitDate   - 訪問日（必須、YYYY-MM-DD）
     *   purpose     - 訪問目的（必須）
     *   summary     - 訪問概要
     *   nextAction  - 次回アクション
     *   rating      - 評価（1-5）
     *   details     - 訪問詳細リスト（オプション）
     */
    @HttpPost
    global static void createVisit() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            Map<String, Object> requestBody = (Map<String, Object>) JSON.deserializeUntyped(
                req.requestBody.toString()
            );

            // バリデーション
            List<String> errors = validateCreateRequest(requestBody);
            if (!errors.isEmpty()) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                    'error' => '入力値が不正です',
                    'code' => 'VALIDATION_ERROR',
                    'details' => errors
                }));
                return;
            }

            StoreVisit__c visit = StoreVisitService.createVisit(requestBody);

            res.statusCode = 201;
            res.responseBody = Blob.valueOf(JSON.serialize(visit));

        } catch (StoreVisitService.BusinessException e) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'error' => e.getMessage(),
                'code' => 'BUSINESS_ERROR'
            }));
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'error' => e.getMessage(),
                'code' => 'INTERNAL_ERROR'
            }));
        }
    }

    /**
     * 訪問記録更新（ステータス遷移含む）
     */
    @HttpPatch
    global static void updateVisit() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            String visitId = req.requestURI.substringAfterLast('/');
            if (String.isBlank(visitId) || visitId == 'store-visits') {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                    'error' => '訪問記録IDが指定されていません',
                    'code' => 'MISSING_ID'
                }));
                return;
            }

            Map<String, Object> requestBody = (Map<String, Object>) JSON.deserializeUntyped(
                req.requestBody.toString()
            );

            StoreVisit__c visit = StoreVisitService.updateVisit(visitId, requestBody);

            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(visit));

        } catch (StoreVisitService.NotFoundException e) {
            res.statusCode = 404;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'error' => e.getMessage(),
                'code' => 'VISIT_NOT_FOUND'
            }));
        } catch (StoreVisitService.BusinessException e) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'error' => e.getMessage(),
                'code' => 'BUSINESS_ERROR'
            }));
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'error' => e.getMessage(),
                'code' => 'INTERNAL_ERROR'
            }));
        }
    }

    /**
     * 訪問記録削除
     * 注意: Draft ステータスの訪問記録のみ削除可能
     */
    @HttpDelete
    global static void deleteVisit() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            String visitId = req.requestURI.substringAfterLast('/');
            if (String.isBlank(visitId) || visitId == 'store-visits') {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                    'error' => '訪問記録IDが指定されていません',
                    'code' => 'MISSING_ID'
                }));
                return;
            }

            StoreVisitService.deleteVisit(visitId);

            res.statusCode = 204;

        } catch (StoreVisitService.NotFoundException e) {
            res.statusCode = 404;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'error' => e.getMessage(),
                'code' => 'VISIT_NOT_FOUND'
            }));
        } catch (StoreVisitService.BusinessException e) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'error' => e.getMessage(),
                'code' => 'BUSINESS_ERROR'
            }));
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'error' => e.getMessage(),
                'code' => 'INTERNAL_ERROR'
            }));
        }
    }

    // ========== Private Methods ==========

    private static List<String> validateCreateRequest(Map<String, Object> body) {
        List<String> errors = new List<String>();

        if (!body.containsKey('storeId') || String.isBlank((String) body.get('storeId'))) {
            errors.add('storeId は必須です');
        }
        if (!body.containsKey('visitDate') || String.isBlank((String) body.get('visitDate'))) {
            errors.add('visitDate は必須です');
        } else {
            try {
                Date.valueOf((String) body.get('visitDate'));
            } catch (Exception e) {
                errors.add('visitDate の形式が不正です（YYYY-MM-DD）');
            }
        }
        if (!body.containsKey('purpose') || String.isBlank((String) body.get('purpose'))) {
            errors.add('purpose は必須です');
        }
        if (body.containsKey('rating')) {
            Object ratingObj = body.get('rating');
            if (ratingObj instanceof Integer || ratingObj instanceof Decimal) {
                Integer rating = Integer.valueOf(ratingObj);
                if (rating < 1 || rating > 5) {
                    errors.add('rating は 1〜5 の範囲で指定してください');
                }
            } else {
                errors.add('rating は数値で指定してください');
            }
        }

        return errors;
    }
}
