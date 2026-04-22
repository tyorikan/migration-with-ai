public with sharing class AccountService {
    /**
     * 取引先（Account）の一覧を取得し、有効なアカウントのみを返す。
     * 古いビジネスロジックが含まれており、結合度が高いコードの例。
     */
    public static List<Account> getActiveAccounts() {
        List<Account> activeAccounts = new List<Account>();
        
        try {
            // DBへの直接アクセス
            // 実際はもっと複雑な条件やSOQLが含まれる想定
            List<Account> accounts = [SELECT Id, Name, Industry, Status__c FROM Account WHERE Status__c = 'Active' LIMIT 50];
            
            for (Account acc : accounts) {
                // 不必要な中間処理や冗長なロジックの例
                if (String.isNotBlank(acc.Name)) {
                    acc.Name = acc.Name.trim();
                    activeAccounts.add(acc);
                }
            }
        } catch (Exception e) {
            // 単純なシステムデバッグログ。本当は適切なエラーハンドリングが必要。
            System.debug('Error fetching accounts: ' + e.getMessage());
            throw new AuraHandledException('取引先の取得中にエラーが発生しました。');
        }
        
        return activeAccounts;
    }
}
