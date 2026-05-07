/**
 * StoreVisitScheduler
 * StoreVisitMonthlyBatch のスケジューラー
 *
 * 実行: 毎月1日 AM 2:00
 * 登録方法:
 *   System.schedule('Monthly Store Visit Summary', '0 0 2 1 * ?', new StoreVisitScheduler());
 */
public class StoreVisitScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {
        StoreVisitMonthlyBatch batch = new StoreVisitMonthlyBatch();
        Database.executeBatch(batch, 50);
    }
}
