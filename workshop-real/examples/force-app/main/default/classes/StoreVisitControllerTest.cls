@isTest
private class StoreVisitControllerTest {

    @TestSetup
    static void setupTestData() {
        // 店舗マスタ
        Store__c store = new Store__c(
            StoreCode__c = 'TEST-001',
            StoreName__c = 'テスト渋谷店',
            Region__c = '関東',
            Address__c = '東京都渋谷区テスト1-2-3',
            Phone__c = '03-0000-0001',
            IsActive__c = true
        );
        insert store;

        // 訪問記録（下書き）
        StoreVisit__c draftVisit = new StoreVisit__c(
            Store__c = store.Id,
            VisitDate__c = Date.today(),
            Status__c = 'Draft',
            Purpose__c = '定期巡回',
            Summary__c = 'テスト用の訪問記録です。',
            NextAction__c = '次回アクション',
            Rating__c = 4
        );
        insert draftVisit;

        // 訪問記録（提出済み）
        StoreVisit__c submittedVisit = new StoreVisit__c(
            Store__c = store.Id,
            VisitDate__c = Date.today().addDays(-7),
            Status__c = 'Submitted',
            Purpose__c = '新商品案内',
            Summary__c = '提出済みの訪問記録。',
            Rating__c = 5
        );
        insert submittedVisit;

        // 訪問記録（承認済み）
        StoreVisit__c approvedVisit = new StoreVisit__c(
            Store__c = store.Id,
            VisitDate__c = Date.today().addDays(-14),
            Status__c = 'Approved',
            Purpose__c = 'クレーム対応',
            Summary__c = '承認済みの訪問記録。',
            Rating__c = 3
        );
        insert approvedVisit;

        // 訪問詳細（アクションアイテム）
        List<VisitDetail__c> details = new List<VisitDetail__c>{
            new VisitDetail__c(
                StoreVisit__c = draftVisit.Id,
                Category__c = '在庫確認',
                Description__c = '夏物の在庫を確認する',
                DueDate__c = Date.today().addDays(7),
                IsCompleted__c = false,
                Priority__c = 1
            ),
            new VisitDetail__c(
                StoreVisit__c = draftVisit.Id,
                Category__c = '販促物設置',
                Description__c = 'POPを設置する',
                DueDate__c = Date.today().addDays(14),
                IsCompleted__c = false,
                Priority__c = 2
            )
        };
        insert details;
    }

    // =========================================================
    // GET: 一覧取得
    // =========================================================

    @isTest
    static void testGetVisits_ReturnsAllRecords() {
        Test.startTest();
        List<StoreVisit__c> result = StoreVisitController.getVisits(null, null, null);
        Test.stopTest();

        System.assertEquals(3, result.size(), '全3件の訪問記録が返ること');
    }

    @isTest
    static void testGetVisits_FilterByStatus() {
        Test.startTest();
        List<StoreVisit__c> result = StoreVisitController.getVisits('Draft', null, null);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Draft のみ1件返ること');
        System.assertEquals('Draft', result[0].Status__c, 'ステータスが Draft であること');
    }

    @isTest
    static void testGetVisits_FilterByStore() {
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];

        Test.startTest();
        List<StoreVisit__c> result = StoreVisitController.getVisits(null, store.Id, null);
        Test.stopTest();

        System.assert(result.size() > 0, '該当店舗の訪問記録が返ること');
        for (StoreVisit__c v : result) {
            System.assertEquals(store.Id, v.Store__c, '店舗IDが一致すること');
        }
    }

    @isTest
    static void testGetVisits_FilterByDateRange() {
        Test.startTest();
        List<StoreVisit__c> result = StoreVisitController.getVisits(
            null, null, Date.today().addDays(-10)
        );
        Test.stopTest();

        for (StoreVisit__c v : result) {
            System.assert(
                v.VisitDate__c >= Date.today().addDays(-10),
                '訪問日がフィルタ条件以降であること'
            );
        }
    }

    // =========================================================
    // GET: 単一取得
    // =========================================================

    @isTest
    static void testGetVisitById_Success() {
        StoreVisit__c visit = [SELECT Id FROM StoreVisit__c WHERE Status__c = 'Draft' LIMIT 1];

        Test.startTest();
        StoreVisit__c result = StoreVisitController.getVisitById(visit.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, '訪問記録が取得できること');
        System.assertEquals(visit.Id, result.Id, 'IDが一致すること');
        // 子レコード（VisitDetail__c）も含まれることを確認
        System.assertEquals(2, result.VisitDetails__r.size(), '訪問詳細が2件含まれること');
    }

    @isTest
    static void testGetVisitById_NotFound() {
        Id fakeId = StoreVisit__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000';

        Test.startTest();
        try {
            StoreVisitController.getVisitById(fakeId);
            System.assert(false, '例外がスローされるべき');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('見つかりません'), 'エラーメッセージに「見つかりません」を含むこと');
        }
        Test.stopTest();
    }

    // =========================================================
    // POST: 新規作成
    // =========================================================

    @isTest
    static void testCreateVisit_Success() {
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];

        Test.startTest();
        StoreVisit__c result = StoreVisitController.createVisit(
            store.Id,
            Date.today(),
            '棚割り変更',
            '新しい訪問記録のサマリー',
            '次回アクション内容',
            4
        );
        Test.stopTest();

        System.assertNotEquals(null, result.Id, 'ID が付与されること');
        System.assertEquals('Draft', result.Status__c, '初期ステータスが Draft であること');
        System.assertEquals(store.Id, result.Store__c, '店舗IDが設定されること');
        System.assertEquals(4, result.Rating__c, '評価が設定されること');
    }

    @isTest
    static void testCreateVisit_MissingRequiredField() {
        Test.startTest();
        try {
            StoreVisitController.createVisit(
                null,       // store_id が null
                Date.today(),
                '定期巡回',
                'サマリー',
                null,
                3
            );
            System.assert(false, '例外がスローされるべき');
        } catch (AuraHandledException e) {
            System.assert(
                e.getMessage().contains('店舗') || e.getMessage().contains('必須'),
                'バリデーションエラーが返ること'
            );
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateVisit_InvalidRating() {
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];

        Test.startTest();
        try {
            StoreVisitController.createVisit(
                store.Id,
                Date.today(),
                '定期巡回',
                'サマリー',
                null,
                6  // Rating は 1-5 の範囲
            );
            System.assert(false, '例外がスローされるべき');
        } catch (AuraHandledException e) {
            System.assert(
                e.getMessage().contains('評価') || e.getMessage().contains('1') || e.getMessage().contains('5'),
                '評価値の範囲エラーが返ること'
            );
        }
        Test.stopTest();
    }

    // =========================================================
    // PATCH: ステータス遷移
    // =========================================================

    @isTest
    static void testUpdateStatus_DraftToSubmitted() {
        StoreVisit__c visit = [SELECT Id FROM StoreVisit__c WHERE Status__c = 'Draft' LIMIT 1];

        Test.startTest();
        StoreVisit__c result = StoreVisitController.updateVisitStatus(visit.Id, 'Submitted');
        Test.stopTest();

        System.assertEquals('Submitted', result.Status__c, 'Draft → Submitted に遷移できること');
    }

    @isTest
    static void testUpdateStatus_SubmittedToApproved() {
        StoreVisit__c visit = [SELECT Id FROM StoreVisit__c WHERE Status__c = 'Submitted' LIMIT 1];

        Test.startTest();
        StoreVisit__c result = StoreVisitController.updateVisitStatus(visit.Id, 'Approved');
        Test.stopTest();

        System.assertEquals('Approved', result.Status__c, 'Submitted → Approved に遷移できること');
    }

    @isTest
    static void testUpdateStatus_SubmittedToRejected() {
        StoreVisit__c visit = [SELECT Id FROM StoreVisit__c WHERE Status__c = 'Submitted' LIMIT 1];

        Test.startTest();
        StoreVisit__c result = StoreVisitController.updateVisitStatus(visit.Id, 'Rejected');
        Test.stopTest();

        System.assertEquals('Rejected', result.Status__c, 'Submitted → Rejected に遷移できること');
    }

    @isTest
    static void testUpdateStatus_InvalidTransition_ApprovedToDraft() {
        StoreVisit__c visit = [SELECT Id FROM StoreVisit__c WHERE Status__c = 'Approved' LIMIT 1];

        Test.startTest();
        try {
            StoreVisitController.updateVisitStatus(visit.Id, 'Draft');
            System.assert(false, '不正遷移で例外がスローされるべき');
        } catch (AuraHandledException e) {
            System.assert(
                e.getMessage().contains('遷移') || e.getMessage().contains('ステータス'),
                '不正なステータス遷移エラーが返ること: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    // =========================================================
    // DELETE: 削除
    // =========================================================

    @isTest
    static void testDeleteVisit_DraftCanBeDeleted() {
        StoreVisit__c visit = [SELECT Id FROM StoreVisit__c WHERE Status__c = 'Draft' LIMIT 1];

        Test.startTest();
        StoreVisitController.deleteVisit(visit.Id);
        Test.stopTest();

        List<StoreVisit__c> remaining = [SELECT Id FROM StoreVisit__c WHERE Id = :visit.Id];
        System.assertEquals(0, remaining.size(), 'Draft の訪問記録が削除されること');

        // CASCADE: 子レコードも削除されること
        List<VisitDetail__c> remainingDetails = [
            SELECT Id FROM VisitDetail__c WHERE StoreVisit__c = :visit.Id
        ];
        System.assertEquals(0, remainingDetails.size(), '訪問詳細も CASCADE 削除されること');
    }

    @isTest
    static void testDeleteVisit_ApprovedCannotBeDeleted() {
        StoreVisit__c visit = [SELECT Id FROM StoreVisit__c WHERE Status__c = 'Approved' LIMIT 1];

        Test.startTest();
        try {
            StoreVisitController.deleteVisit(visit.Id);
            System.assert(false, '承認済みレコードの削除で例外がスローされるべき');
        } catch (AuraHandledException e) {
            System.assert(
                e.getMessage().contains('削除') || e.getMessage().contains('Draft'),
                '承認済みレコードは削除できないエラーが返ること'
            );
        }
        Test.stopTest();
    }
}
