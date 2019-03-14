# frozen_string_literal: true

class Form::AccountBatch
  include ActiveModel::Model

  attr_accessor :account_ids, :action, :current_account

  def save
    case action
    when 'remove_from_followers'
      remove_from_followers!
    end
  end

  private

  def remove_from_followers!
    current_account.passive_relations.where(account_id: account_ids).find_each do |follow|
      reject_follow!(follow)
    end
  end

  def reject_follow!(follow)
    follow.destroy

    return unless follow.account.activitypub?

    json = ActiveModelSerializers::SerializableResource.new(
      follow,
      serializer: ActivityPub::RejectFollowSerializer,
      adapter: ActivityPub::Adapter
    ).to_json

    ActivityPub::DeliveryWorker.perform_async(json, current_account.id, follow.account.inbox_url)
  end
end
