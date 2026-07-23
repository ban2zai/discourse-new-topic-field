# frozen_string_literal: true

module DiscourseNewTopicField
  class TopicsController < ::ApplicationController
    requires_plugin DiscourseNewTopicField::PLUGIN_NAME

    skip_before_action :redirect_to_login_if_required, only: %i[by_guid by_topic]

    before_action :ensure_enabled
    before_action :ensure_lookup_token, only: %i[by_guid by_topic]
    before_action :ensure_logged_in, only: %i[update_guid destroy_guid]

    def index
      guid = normalized_param_guid
      return render_json_error(I18n.t("discourse_new_topic_field.errors.guid_required"), status: 422) if guid.blank?

      authorize_external_search!

      topic = DiscourseNewTopicField.topic_for_guid(guid)
      topics = visible_topic?(topic) ? [topic_payload(topic, guid)] : []

      render json: {
               linked: topic.present?,
               topics: topics,
             }
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
      payload =
        failed_json.merge(
          errors: [I18n.t("discourse_new_topic_field.errors.guid_already_linked")],
        )
      payload[:topic] = topic_payload(error.topic, guid) if visible_topic?(error.topic)

      render(
        json: payload,
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

    def visible_topic?(topic)
      topic.present? && topic.visible && topic.deleted_at.blank? &&
        topic.archetype == Archetype.default && guardian.can_see?(topic)
    end

    def authorize_external_search!
      # MVP intentionally has no external token check. Add it here before exposing
      # private integration access.
      true
    end

    def lookup_payload(topic, topic_id: nil, guid: nil)
      if topic.present?
        solution_status = solution_status_payload(topic)

        {
          ok: true,
          found: true,
          topic_id: topic.id,
          guid: guid,
          title: topic.title,
          slug: topic.slug,
          url: Discourse.base_url + topic.relative_url,
          created_at: topic.created_at,
          category: category_payload(topic),
          can_set_solution: solution_status[:can_set_solution],
          has_solution: solution_status[:has_solution],
          solution: solution_status[:solution],
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

      payload = ::TzApproval.topic_status_payload(topic)
      approvals = payload[:approvals] || payload["approvals"]

      {
        available: true,
        data: approval_profiles_payload(approvals),
      }
    rescue StandardError
      approval_status_unavailable
    end

    def approval_profiles_payload(approvals)
      Array(approvals).each_with_object({}) do |approval, payload|
        approval = approval.with_indifferent_access
        prefix = approval[:profile_prefix].to_s
        next unless prefix.match?(/\A[a-z0-9_]+\z/)

        approved_by = (approval[:approved_by] || {}).with_indifferent_access
        payload["is_#{prefix}"] = approval[:is_applicable] == true
        payload["#{prefix}_approved"] = approval[:approved] == true
        payload["#{prefix}_approved_by"] = {
          id: approved_by[:id],
          username: approved_by[:username],
          at: approved_by[:at],
        }
      end
    end

    def approval_status_unavailable
      {
        available: false,
        data: nil,
      }
    end

    def category_payload(topic)
      category = topic.category

      {
        category_name: category&.name,
        category_id: topic.category_id,
        category_slug: category&.slug,
      }
    end

    def solution_status_payload(topic)
      return empty_solution_status unless defined?(::DiscourseSolved::SolvedTopic)

      solved_topic = ::DiscourseSolved::SolvedTopic.find_by(topic_id: topic.id)
      answer_post_id = solved_topic&.answer_post_id
      answer_post = Post.find_by(id: answer_post_id) if answer_post_id.present?
      solution_marker = User.find_by(id: solved_topic.accepter_user_id) if solved_topic.present?
      has_solution = answer_post_id.present?

      {
        can_set_solution:
          solved_enabled_for_topic?(topic) && (has_solution || topic_has_reply?(topic)),
        has_solution: has_solution,
        solution: {
          post_id: answer_post_id,
          marked_at: solved_topic&.created_at,
          marked_by: {
            id: solution_marker&.id,
            username: solution_marker&.username,
          },
          post_author: {
            id: answer_post&.user_id,
            username: answer_post&.user&.username,
          },
        },
      }
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      empty_solution_status
    end

    def empty_solution_status
      {
        can_set_solution: false,
        has_solution: false,
        solution: {
          post_id: nil,
          marked_at: nil,
          marked_by: {
            id: nil,
            username: nil,
          },
          post_author: {
            id: nil,
            username: nil,
          },
        },
      }
    end

    def solved_enabled_for_topic?(topic)
      field_name =
        if defined?(::DiscourseSolved::ENABLE_ACCEPTED_ANSWERS_CUSTOM_FIELD)
          ::DiscourseSolved::ENABLE_ACCEPTED_ANSWERS_CUSTOM_FIELD
        else
          "enable_accepted_answers"
        end
      value = CategoryCustomField.find_by(category_id: topic.category_id, name: field_name)&.value

      value == true || value == "true" || value == "t" || value == "1"
    end

    def topic_has_reply?(topic)
      Post.where(topic_id: topic.id, deleted_at: nil).where("post_number > 1").exists?
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
