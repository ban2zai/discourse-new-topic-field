# frozen_string_literal: true

module DiscourseNewTopicField
  class TopicsController < ::ApplicationController
    requires_plugin DiscourseNewTopicField::PLUGIN_NAME

    before_action :ensure_enabled
    before_action :ensure_lookup_token, only: %i[by_guid by_topic]
    before_action :ensure_logged_in, only: %i[update_guid destroy_guid]

    def index
      guid = normalized_param_guid
      return render_json_error(I18n.t("discourse_new_topic_field.errors.guid_required"), status: 422) if guid.blank?

      authorize_external_search!

      topic = DiscourseNewTopicField.topic_for_guid(guid)
      topics =
        if topic && topic.visible && topic.deleted_at.blank? && topic.archetype == Archetype.default &&
             guardian.can_see?(topic)
          [topic_payload(topic, guid)]
        else
          []
        end

      render json: { topics: topics }
    end

    def update_guid
      topic = Topic.find(params[:topic_id])
      guardian.ensure_can_manage_task_guid!(topic)

      guid = normalized_param_guid
      return render_json_error(I18n.t("discourse_new_topic_field.errors.guid_required"), status: 422) if guid.blank?

      DiscourseNewTopicField.store_topic_guid(topic, guid)
      MessageBus.publish("/topic/#{topic.id}", reload_topic: true, refresh_stream: true)

      render json: success_json.merge(topic_payload(topic, guid))
    rescue DiscourseNewTopicField::DuplicateGuidError => error
      render(
        json:
          failed_json.merge(
            errors: [I18n.t("discourse_new_topic_field.errors.guid_already_linked")],
            topic: topic_payload(error.topic, guid),
          ),
        status: 409,
      )
    end

    def validate_signature
      guid = normalized_param_guid
      return render_json_error(I18n.t("discourse_new_topic_field.errors.guid_required"), status: 422) if guid.blank?

      if DiscourseNewTopicField.valid_signature?(
           guid: guid,
           expires: params[:expires],
           nonce: params[:nonce],
           sig: params[:sig],
         )
        render json: success_json
      else
        render_json_error(I18n.t("discourse_new_topic_field.errors.invalid_signature"), status: 403)
      end
    end

    def destroy_guid
      topic = Topic.find(params[:topic_id])
      guardian.ensure_can_manage_task_guid!(topic)

      DiscourseNewTopicField.clear_topic_guid(topic)
      MessageBus.publish("/topic/#{topic.id}", reload_topic: true, refresh_stream: true)

      render json: success_json.merge(topic_payload(topic, nil))
    end

    def by_guid
      guid = normalized_param_guid
      topic = guid.present? ? DiscourseNewTopicField.topic_for_guid(guid) : nil

      render json: lookup_payload(topic, guid: guid)
    end

    def by_topic
      topic_id = Integer(params[:topic_id], exception: false)
      topic = topic_id.present? ? Topic.find_by(id: topic_id) : nil
      guid = topic.present? ? topic_guid(topic) : nil

      render json: lookup_payload(topic, topic_id: topic_id, guid: guid)
    end

    private

    def ensure_enabled
      raise Discourse::NotFound unless SiteSetting.discourse_new_topic_field_enabled
    end

    def ensure_lookup_token
      return if DiscourseNewTopicField.lookup_token_valid?(params[:token])

      render json: {
               ok: false,
               error: "invalid_token",
             },
             status: 403
    end

    def normalized_param_guid
      DiscourseNewTopicField.normalize_guid(params[:guid])
    end

    def authorize_external_search!
      # MVP intentionally has no external token check. Add it here before exposing
      # private integration access.
      true
    end

    def lookup_payload(topic, topic_id: nil, guid: nil)
      if topic.present?
        {
          ok: true,
          found: true,
          topic_id: topic.id,
          guid: guid,
          title: topic.title,
          slug: topic.slug,
          url: Discourse.base_url + topic.relative_url,
          created_at: topic.created_at,
          approval_status: approval_status_payload(topic),
        }
      else
        {
          ok: true,
          found: false,
          topic_id: topic_id,
          guid: guid,
          approval_status: approval_status_payload(nil),
        }
      end
    end

    def topic_guid(topic)
      topic.custom_fields[DiscourseNewTopicField::FIELD_NAME].presence ||
        TopicCustomField.find_by(topic_id: topic.id, name: DiscourseNewTopicField::FIELD_NAME)&.value
    end

    def approval_status_payload(topic)
      return approval_status_unavailable if topic.blank?
      return approval_status_unavailable unless defined?(::TzApproval)
      return approval_status_unavailable unless ::TzApproval.respond_to?(:topic_status_payload)

      {
        available: true,
        data: ::TzApproval.topic_status_payload(topic),
      }
    rescue StandardError
      approval_status_unavailable.merge(error: "unavailable")
    end

    def approval_status_unavailable
      {
        available: false,
        data: nil,
      }
    end

    def topic_payload(topic, guid)
      {
        topic_id: topic.id,
        title: topic.title,
        slug: topic.slug,
        url: Discourse.base_url + topic.relative_url,
        created_at: topic.created_at,
        guid: guid,
      }
    end
  end
end
