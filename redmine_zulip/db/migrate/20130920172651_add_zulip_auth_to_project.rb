class AddZulipAuthToProject < ActiveRecord::Migration
    def change
        add_column :projects, :zulip_email, :string, :default => "", :null => false
        add_column :projects, :zulip_api_key, :string, :default => "", :null => false
        add_column :projects, :zulip_stream, :string, :default => "", :null => false
        add_column :projects, :zulip_message_new, :text, :default => "", :null => false
        add_column :projects, :zulip_message_edit, :text, :default => "", :null => false
    end
end
