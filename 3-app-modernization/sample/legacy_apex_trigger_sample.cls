trigger AccountTrigger on Account (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            for (Account acc : Trigger.new) {
                // IndustryがTechnologyの場合、RatingをHotに設定
                if (acc.Industry == 'Technology' && acc.Rating == null) {
                    acc.Rating = 'Hot';
                }

                // BillingStateがCaliforniaの場合、自動的にテリトリーコードを割り当て
                if (acc.BillingState == 'CA' || acc.BillingState == 'California') {
                    acc.Custom_Territory_Code__c = 'WEST-01';
                }

                // 外部システムとの連携用に独自のIDを生成 (例)
                if (String.isBlank(acc.External_Sync_Id__c)) {
                    acc.External_Sync_Id__c = 'SYNC-' + System.currentTimeMillis();
                }
            }
        }
    }
}
