import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import createStoreVisit from '@salesforce/apex/StoreVisitController.createVisitFromLwc';

const PURPOSE_OPTIONS = [
    { label: '定期巡回', value: '定期巡回' },
    { label: '新商品案内', value: '新商品案内' },
    { label: 'クレーム対応', value: 'クレーム対応' },
    { label: '棚割り変更', value: '棚割り変更' },
    { label: 'キャンペーン設置', value: 'キャンペーン設置' },
    { label: 'その他', value: 'その他' }
];

const CATEGORY_OPTIONS = [
    { label: '商品配置', value: '商品配置' },
    { label: '販促物設置', value: '販促物設置' },
    { label: '在庫確認', value: '在庫確認' },
    { label: '価格交渉', value: '価格交渉' },
    { label: 'クレーム', value: 'クレーム' },
    { label: 'その他', value: 'その他' }
];

export default class StoreVisitForm extends NavigationMixin(LightningElement) {
    @api recordId; // 既存レコード編集時に使用

    @track storeId = '';
    @track visitDate = new Date().toISOString().split('T')[0]; // 今日の日付をデフォルト
    @track purpose = '定期巡回';
    @track summary = '';
    @track nextAction = '';
    @track rating = 0;
    @track details = [];

    _detailIdCounter = 0;

    get purposeOptions() {
        return PURPOSE_OPTIONS;
    }

    get categoryOptions() {
        return CATEGORY_OPTIONS;
    }

    get ratingStars() {
        const stars = [];
        for (let i = 1; i <= 5; i++) {
            stars.push({
                value: i,
                icon: i <= this.rating ? 'utility:favorite' : 'utility:favorite_alt'
            });
        }
        return stars;
    }

    get ratingLabel() {
        const labels = { 1: '不良', 2: '要改善', 3: '普通', 4: '良好', 5: '優秀' };
        return this.rating > 0 ? `${this.rating} - ${labels[this.rating]}` : '未評価';
    }

    // ========== Event Handlers ==========

    handleStoreChange(event) {
        this.storeId = event.detail.recordId;
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.target.value;
    }

    handleRatingClick(event) {
        this.rating = parseInt(event.currentTarget.dataset.value, 10);
    }

    handleAddDetail() {
        this.details = [
            ...this.details,
            {
                id: ++this._detailIdCounter,
                category: 'その他',
                description: '',
                priority: 3,
                dueDate: ''
            }
        ];
    }

    handleRemoveDetail(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.details = this.details.filter((_, i) => i !== index);
    }

    handleDetailChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const field = event.target.dataset.field;
        const value = event.target.value;

        this.details = this.details.map((detail, i) => {
            if (i === index) {
                return { ...detail, [field]: value };
            }
            return detail;
        });
    }

    handleCancel() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'StoreVisit__c',
                actionName: 'list'
            }
        });
    }

    async handleSaveDraft() {
        await this._saveVisit('Draft');
    }

    async handleSubmit() {
        await this._saveVisit('Submitted');
    }

    // ========== Private Methods ==========

    async _saveVisit(status) {
        // バリデーション
        if (!this.storeId) {
            this._showToast('エラー', '店舗を選択してください', 'error');
            return;
        }
        if (!this.visitDate) {
            this._showToast('エラー', '訪問日を入力してください', 'error');
            return;
        }

        try {
            const payload = {
                storeId: this.storeId,
                visitDate: this.visitDate,
                purpose: this.purpose,
                summary: this.summary,
                nextAction: this.nextAction,
                rating: this.rating > 0 ? this.rating : null,
                status: status,
                details: this.details
                    .filter(d => d.description || d.category !== 'その他')
                    .map(d => ({
                        category: d.category,
                        description: d.description,
                        priority: parseInt(d.priority, 10),
                        dueDate: d.dueDate || null
                    }))
            };

            const result = await createStoreVisit({ requestJson: JSON.stringify(payload) });

            this._showToast(
                '成功',
                status === 'Draft' ? '下書きとして保存しました' : '提出しました',
                'success'
            );

            // 作成されたレコードに遷移
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: result.Id,
                    objectApiName: 'StoreVisit__c',
                    actionName: 'view'
                }
            });
        } catch (error) {
            this._showToast('エラー', error.body?.message || error.message, 'error');
        }
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
