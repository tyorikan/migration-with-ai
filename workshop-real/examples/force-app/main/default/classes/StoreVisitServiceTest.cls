@isTest
private class StoreVisitServiceTest {

    @TestSetup
    static void setupTestData() {
        Store__c store = new Store__c(
            StoreCode__c = 'SVC-TEST-001',
            StoreName__c = 'サービステスト店',
            Region__c = '関東',
            Address__c = '東京都千代田区テスト1-1',
            IsActive__c = true
        );
        insert store;

        StoreVisit__c visit = new StoreVisit__c(
            Store__c = store.Id,
            VisitDate__c = Date.today(),
            Status__c = 'Draft',
            Purpose__c = '定期巡回',
            Summary__c = 'テスト用',
            Rating__c = 3
        );
        insert visit;
    }

    // =========================================================
    // ステータス遷移ルール検証
    // =========================================================

    @isTest
    static void testValidateTransition_DraftToSubmitted_IsValid() {
        Test.startTest();
        Boolean result = StoreVisitService.isValidTransition('Draft', 'Submitted');
        Test.stopTest();
        System.assertEquals(true, result, 'Draft → Submitted は有効な遷移');
    }

    @isTest
    static void testValidateTransition_SubmittedToApproved_IsValid() {
        Test.startTest();
        Boolean result = StoreVisitService.isValidTransition('Submitted', 'Approved');
        Test.stopTest();
        System.assertEquals(true, result, 'Submitted → Approved は有効な遷移');
    }

    @isTest
    static void testValidateTransition_SubmittedToRejected_IsValid() {
        Test.startTest();
        Boolean result = StoreVisitService.isValidTransition('Submitted', 'Rejected');
        Test.stopTest();
        System.assertEquals(true, result, 'Submitted → Rejected は有効な遷移');
    }

    @isTest
    static void testValidateTransition_RejectedToDraft_IsValid() {
        Test.startTest();
        Boolean result = StoreVisitService.isValidTransition('Rejected', 'Draft');
        Test.stopTest();
        System.assertEquals(true, result, 'Rejected → Draft は有効な遷移（差し戻し後の再編集）');
    }

    @isTest
    static void testValidateTransition_ApprovedToDraft_IsInvalid() {
        Test.startTest();
        Boolean result = StoreVisitService.isValidTransition('Approved', 'Draft');
        Test.stopTest();
        System.assertEquals(false, result, 'Approved → Draft は無効な遷移');
    }

    @isTest
    static void testValidateTransition_DraftToApproved_IsInvalid() {
        Test.startTest();
        Boolean result = StoreVisitService.isValidTransition('Draft', 'Approved');
        Test.stopTest();
        System.assertEquals(false, result, 'Draft → Approved は無効（Submitted を経由すべき）');
    }

    // =========================================================
    // 訪問記録の更新 + Trigger 連動
    // =========================================================

    @isTest
    static void testUpdateVisit_UpdatesStoreLastVisitDate() {
        StoreVisit__c visit = [SELECT Id, Store__c, VisitDate__c FROM StoreVisit__c LIMIT 1];

        Test.startTest();
        visit.Status__c = 'Submitted';
        update visit;
        Test.stopTest();

        // Trigger により Store__c の LastVisitDate__c が更新されること
        Store__c store = [SELECT LastVisitDate__c FROM Store__c WHERE Id = :visit.Store__c];
        System.assertEquals(
            visit.VisitDate__c,
            store.LastVisitDate__c,
            '訪問記録の更新時に店舗の最終訪問日が更新されること'
        );
    }

    @isTest
    static void testUpdateVisit_UpdatesStoreAverageRating() {
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];

        // 追加の訪問記録を作成（Rating = 5）
        StoreVisit__c visit2 = new StoreVisit__c(
            Store__c = store.Id,
            VisitDate__c = Date.today(),
            Status__c = 'Submitted',
            Purpose__c = '新商品案内',
            Summary__c = '2件目の訪問',
            Rating__c = 5
        );
        insert visit2;

        Test.startTest();
        // 既存（Rating=3）+ 新規（Rating=5）の平均 = 4.0
        Store__c updatedStore = [SELECT AverageRating__c FROM Store__c WHERE Id = :store.Id];
        Test.stopTest();

        System.assertEquals(
            4.0,
            updatedStore.AverageRating__c,
            '平均評価が正しく計算されること（(3+5)/2 = 4.0）'
        );
    }

    // =========================================================
    // バリデーション
    // =========================================================

    @isTest
    static void testRatingValidation_MinValue() {
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];

        Test.startTest();
        try {
            StoreVisit__c visit = new StoreVisit__c(
                Store__c = store.Id,
                VisitDate__c = Date.today(),
                Status__c = 'Draft',
                Purpose__c = '定期巡回',
                Summary__c = 'テスト',
                Rating__c = 0  // 範囲外（1-5）
            );
            insert visit;
            System.assert(false, 'バリデーションエラーがスローされるべき');
        } catch (Exception e) {
            System.assert(true, '範囲外の Rating でエラーが発生すること');
        }
        Test.stopTest();
    }

    @isTest
    static void testRatingValidation_MaxValue() {
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];

        Test.startTest();
        try {
            StoreVisit__c visit = new StoreVisit__c(
                Store__c = store.Id,
                VisitDate__c = Date.today(),
                Status__c = 'Draft',
                Purpose__c = '定期巡回',
                Summary__c = 'テスト',
                Rating__c = 6  // 範囲外（1-5）
            );
            insert visit;
            System.assert(false, 'バリデーションエラーがスローされるべき');
        } catch (Exception e) {
            System.assert(true, '範囲外の Rating でエラーが発生すること');
        }
        Test.stopTest();
    }

    // =========================================================
    // 削除の条件
    // =========================================================

    @isTest
    static void testCanDelete_DraftOnly() {
        Test.startTest();
        System.assertEquals(true, StoreVisitService.canDelete('Draft'), 'Draft は削除可能');
        System.assertEquals(false, StoreVisitService.canDelete('Submitted'), 'Submitted は削除不可');
        System.assertEquals(false, StoreVisitService.canDelete('Approved'), 'Approved は削除不可');
        System.assertEquals(false, StoreVisitService.canDelete('Rejected'), 'Rejected は削除不可');
        Test.stopTest();
    }
}
