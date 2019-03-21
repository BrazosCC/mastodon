# frozen_string_literal: true

module Omniauthable
  extend ActiveSupport::Concern

  TEMP_EMAIL_PREFIX = 'change@me'
  TEMP_EMAIL_REGEX = /\Achange@me/

  included do
    devise :omniauthable

    def omniauth_providers
      Devise.omniauth_configs.keys
    end

    def email_verified?
      email && email !~ TEMP_EMAIL_REGEX
    end
  end

  class_methods do
    def find_for_oauth(auth, signed_in_resource = nil)
      Rails.logger.info("signed_in_resource=#{signed_in_resource}")
      Rails.logger.info("auth=#{auth}")

      # EOLE-SSO Patch
      auth.uid = (auth.uid[0][:uid] || auth.uid[0][:user]) if auth.uid.is_a? Hashie::Array
      if !auth.uid
        auth.uid = auth.extra.user if auth.extra.user
      end
      if !auth.info.verified
        auth.info.verified = auth.extra.verified if auth.extra.verified
      end
      if !auth.info.email
        auth.info.email = auth.extra.email if auth.extra.email
      end
      if !auth.info.email
        auth.info.email = auth.extra.verified_email if auth.extra.verified_email
      end
      if !auth.info.full_name
        auth.info.full_name = auth.extra.full_name if auth.extra.full_name
      end
      if !auth.info.image
        auth.info.image = auth.extra.image if auth.extra.image
      end

      identity = Identity.find_for_oauth(auth)
      Rails.logger.info("identity=#{identity}")
      Rails.logger.info("identity.user=#{identity.user}")

      # If a signed_in_resource is provided it always overrides the existing user
      # to prevent the identity being locked with accidentally created accounts.
      # Note that this may leave zombie accounts (with no associated identity) which
      # can be cleaned up at a later date.
      user = signed_in_resource || identity.user
      Rails.logger.info("found=#{user}")
      Rails.logger.info("auth.uid=#{auth.uid}")
      by_email = User.find_by(email: auth.info.email)
      Rails.logger.info("existing_by_email=#{by_email}")
      by_username = Account.find_by(username: auth.uid)
      Rails.logger.info("existing_by_username=#{by_username}")
      user = by_email if user.nil?
      user = (by_username.user if by_username) if user.nil?
      user = create_for_oauth(auth) if user.nil?
      Rails.logger.info("using=#{user}")

      if identity.user.nil?
        identity.user = user
        identity.save!
      end

      user
    end

    def create_for_oauth(auth)
      # Check if the user exists with provided email if the provider gives us a
      # verified email.  If no verified email was provided or the user already
      # exists, we assign a temporary email and ask the user to verify it on
      # the next step via Auth::ConfirmationsController.finish_signup
      params = user_params_from_auth(auth)
      Rails.logger.info("params=#{params}")
      user = User.new(params)
      user.account.avatar_remote_url = auth.info.image if auth.info.image =~ /\A#{URI.regexp(%w(http https))}\z/
      user.skip_confirmation!
      user.save!
      user
    end

    private

    def user_params_from_auth(auth)
      strategy          = Devise.omniauth_configs[auth.provider.to_sym].strategy
      assume_verified   = strategy.try(:security).try(:assume_email_is_verified)
      email_is_verified = auth.info.verified || auth.info.verified_email || assume_verified
      email             = auth.info.verified_email || auth.info.email
      email             = email_is_verified && !User.exists?(email: auth.info.email) && email
      display_name      = auth.info.full_name || [auth.info.first_name, auth.info.last_name].join(' ')

      {
        email: email || "#{TEMP_EMAIL_PREFIX}-#{auth.uid}-#{auth.provider}.com",
        password: Devise.friendly_token[0, 20],
        agreement: true,
        account_attributes: {
          username: ensure_unique_username(auth.uid),
          display_name: display_name,
        },
      }
    end

    def ensure_unique_username(starting_username)
      username = starting_username
      i        = 0

      while Account.exists?(username: username)
        i       += 1
        username = "#{starting_username}_#{i}"
      end

      username
    end
  end
end
