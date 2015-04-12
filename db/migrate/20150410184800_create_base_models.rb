class CreateBaseModels < ActiveRecord::Migration
  def change
    create_table :koodo_transactions do |t|
      t.integer :koodo_id
      t.date :date
      t.string :description
      t.integer :credit
      t.integer :debit
      t.timestamps
    end

    create_table :usage_data_points do |t|
      t.float :minutes_remaining
      t.float :mb_remaining
      t.timestamps
    end
  end
end
