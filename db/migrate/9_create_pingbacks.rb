class CreatePingbacks < ActiveRecord::Migration
  def self.up
    create_table :pingbacks do |t|
      t.string :source_uri
      t.string :title
      t.integer :blog_post_id
      t.timestamps
    end

    add_index :pingbacks, [:blog_post_id, :source_uri]
    add_index :pingbacks, [:blog_post_id, :created_at]
  end

  def self.down
    drop_table :pingbacks
  end
end
