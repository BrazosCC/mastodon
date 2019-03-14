# frozen_string_literal: true

class Settings::FollowerDomainsController < Settings::BaseController
  layout 'admin'

  before_action :authenticate_user!
  before_action :set_followers, only: :show

  def show
    @form = Form::AccountBatch.new
  end

  def update
    @form = Form::AccountBatch.new(form_account_batch_params.merge(current_account: current_account, action: action_from_button))
    @form.save
  rescue ActionController::ParameterMissing
    # Do nothing
  ensure
    redirect_to settings_follower_domains_path(current_params)
  end

  private

  def set_followers
    @followers = current_account.followers.includes(:account_stat).page(params[:page]).per(40)
  end

  def form_account_batch_params
    params.require(:form_account_batch_params).permit(:action, account_ids: [])
  end

  def current_params
    { page: (params[:page] || 1).to_i }
  end

  def action_from_button
    'remove_from_followers' if params[:delete]
  end
end
