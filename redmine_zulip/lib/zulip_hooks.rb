# encoding: utf-8

require 'json'

class NotificationHook < Redmine::Hook::Listener
    include ApplicationHelper
    include CustomFieldsHelper
    # We generate Zulips for creating and updating issues.

    def controller_issues_new_after_save(context = {})
        issue = context[:issue]
        project = issue.project

        if !configured(project)
            # Fail silently: the rest of the app needs to continue working.
             return true
        end

        msg = project.zulip_message_new
        msg = Setting.plugin_redmine_zulip[:zulip_message_new] if msg == ""
        content = zulip_message(context, msg)

        send_zulip_message(content, project)
    end

    def controller_issues_edit_after_save(context = {})
        issue = context[:issue]
        project = issue.project

        if !configured(project)
            # Fail silently: the rest of the app needs to continue working.
             return true
        end

        msg = project.zulip_message_edit
        msg = Setting.plugin_redmine_zulip[:zulip_message_edit] if msg == ""
        content = zulip_message(context, msg)

        send_zulip_message(content, project)
    end

    private

    def configured(project)
        # The plugin can be configured as a system setting or per-project.

        if !project.zulip_email.empty? && !project.zulip_api_key.empty? &&
           !project.zulip_stream.empty? && Setting.plugin_redmine_zulip[:projects] &&
            Setting.plugin_redmine_zulip[:zulip_server]
            # We have full per-project settings.
            return true
        elsif Setting.plugin_redmine_zulip[:projects] &&
            Setting.plugin_redmine_zulip[:zulip_email] &&
            Setting.plugin_redmine_zulip[:zulip_api_key] &&
            Setting.plugin_redmine_zulip[:zulip_stream] &&
            Setting.plugin_redmine_zulip[:zulip_server]
            # We have full global settings.
            return true
        end

        Rails.logger.info "Missing config, can't sent to Zulip!"
        return false
    end

    def zulip_message(context, msg_template)
        issue = context[:issue]
        project = issue.project

        std_fields = %(id tracker status priority author assigned_to subject description notes start_date due_date done_ratio spent_hours)
        msg = msg_template
        msg.gsub!(/%\{([^\}]+)\}/) do |v|
            word = $1
            case word
            when 'username' then User.current.name
            when 'url' then url(issue)
            when 'projectname' then project.name
            when /^(.+?)(:([^:]+))?$/ then
                str = $1
                cond = $3
                if cond then
                    tracker = issue.tracker.to_s
                    next "" if tracker != cond
                end
                if std_fields.include?(str) then
                    issue.__send__(str).to_s
                elsif str =~ /^'(.*)'$/ then
                    $1
                else
                    cv = issue.custom_field_values.detect {|c| c.custom_field.name == str}
                    cv ? show_value(cv, false) : word
                end
            else word
            end
        end
        return msg
    end

    def zulip_email(project)
        if !project.zulip_email.empty?
            return project.zulip_email
        end
        return Setting.plugin_redmine_zulip[:zulip_email]
    end

    def zulip_api_key(project)
        if !project.zulip_api_key.empty?
            return project.zulip_api_key
        end
        return Setting.plugin_redmine_zulip[:zulip_api_key]
    end

    def zulip_stream(project)
        if !project.zulip_stream.empty?
            return project.zulip_stream
        end
        return Setting.plugin_redmine_zulip[:zulip_stream]
    end

    def zulip_server()
        return Setting.plugin_redmine_zulip[:zulip_server]
    end
   
    def zulip_port()
        if Setting.plugin_redmine_zulip[:zulip_port]
            return Setting.plugin_redmine_zulip[:zulip_port]
        end
        return 443
    end

    def zulip_api_basename()
        if Setting.plugin_redmine_zulip[:zulip_server]["api.zulip.com"]
            return ""
        end
        return "/api"
    end

    def url(issue)
        return "#{Setting[:protocol]}://#{Setting[:host_name]}/issues/#{issue.id}"
    end

    def send_zulip_message(content, project)

        data = {"to" => zulip_stream(project),
                "type" => "stream",
                "subject" => project.name,
                "content" => content}

        Rails.logger.info "Forwarding to Zulip: #{data['content']}"

        http = Net::HTTP.new(zulip_server(), zulip_port())
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE

        req = Net::HTTP::Post.new(zulip_api_basename() + "/v1/messages")
        req.basic_auth zulip_email(project), zulip_api_key(project)
        req.add_field('User-Agent', 'ZulipRedmine/0.1')
        req.set_form_data(data)

        begin
            http.request(req)
        rescue => e
            Rails.logger.error "Error while POSTing to Zulip: #{e}"
        end
    end
end
