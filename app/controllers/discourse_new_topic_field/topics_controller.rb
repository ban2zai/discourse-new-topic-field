# frozen_string_literal: true

module DiscourseNewTopicField
  class TopicsController < ::ApplicationController
    requires_plugin DiscourseNewTopicField::PLUGIN_NAME

    before_action :ensure_enabled
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

    def destroy_guid
      topic = Topic.find(params[:topic_id])
      guardian.ensure_can_manage_task_guid!(topic)

      DiscourseNewTopicField.clear_topic_guid(topic)
      MessageBus.publish("/topic/#{topic.id}", reload_topic: true, refresh_stream: true)

      render json: success_json.merge(topic_payload(topic, nil))
    end

    private

    def ensure_enabled
      raise Discourse::NotFound unless SiteSetting.discourse_new_topic_field_enabled
    end

    def normalized_param_guid
      DiscourseNewTopicField.normalize_guid(params[:guid])
    end

    def authorize_external_search!
      # MVP intentionally has no external token check. Add it here before exposing
      # private integration access.
      true
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
