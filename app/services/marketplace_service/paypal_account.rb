module MarketplaceService
  module PaypalAccount
    PaypalAccountModel = ::PaypalAccount

    module Entity
      PaypalAccount = EntityUtils.define_entity(
        :email,
        :api_password,
        :api_signature,
        :person_id,
        :community_id,
        :order_permission_state, # one of :not_requested, :pending, :verified
        :request_token # order permission request token
      )

      module_function

      def paypal_account(paypal_acc_model)
        hash = EntityUtils.model_to_hash(paypal_acc_model)
          .merge(order_permission_to_hash(paypal_acc_model.order_permission))
        PaypalAccount.call(hash)
      end


      def order_permission_to_hash(order_perm_model)
        if (order_perm_model.nil?)
          { order_permission_state: :not_requested }
        elsif (order_perm_model.verification_code.nil?)
          { order_permission_state: :pending }
        else
          { order_permission_state: :verified }
        end
          .merge(EntityUtils.model_to_hash(order_perm_model))
      end

      def verified_account?(paypal_account)
        return (paypal_account && paypal_account[:order_permission_state] == :verified)
      end

    end

    module Command

      module_function

      def create_personal_account(person_id, community_id, account_data)
        old_account = PaypalAccountModel
          .where(person_id: person_id, community_id: community_id)
          .eager_load(:order_permission)
          .first

        old_account.destroy if old_account.present?

        PaypalAccountModel.create!(
          account_data.merge({person_id: person_id, community_id: community_id})
        )
        Result::Success.new
      end

      def destroy_personal_account(person_id, community_id)
        Maybe(PaypalAccountModel.where(person_id: person_id, community_id: community_id))
          .map { |paypal_account|
            paypal_account.destroy ? true : false;
          }
      end

      def create_admin_account(community_id, account_data)
        PaypalAccountModel.create!(
          account_data.merge({community_id: community_id, person_id: nil}))
        Result::Success.new
      end

      def create_pending_permissions_request(person_id, community_id, paypal_username_to, permissions_scope, request_token)
        Maybe(PaypalAccountModel
            .where(person_id: person_id, community_id: community_id)
            .eager_load(:order_permission)
            .first
          )
          .map { |paypal_account|

            Maybe(paypal_account.order_permission).destroy

            OrderPermission.create!(
              {
                paypal_account: paypal_account,
                request_token: request_token,
                paypal_username_to: paypal_username_to,
                scope: permissions_scope.join(',')
              }
            )
            true
          }
          .or_else(false)
      end

      def confirm_pending_permissions_request(person_id, community_id, request_token, verification_code)
        # Should this fail silently in case of no matching permission request?
        order_permission =  OrderPermission
          .eager_load(:paypal_account)
          .where({
            :request_token => request_token,
            "paypal_accounts.person_id" => person_id,
            "paypal_accounts.community_id" => community_id
          })
          .first
        if order_permission.present?
            order_permission[:verification_code] = verification_code
            order_permission.save!
            true
        else
          false
        end
      end
    end

    module Query

      module_function

      def personal_account(person_id, community_id)
        Maybe(PaypalAccountModel
            .where(person_id: person_id, community_id: community_id)
            .eager_load(:order_permission)
            .first
          )
          .map { |model| Entity.paypal_account(model) }
          .or_else(nil)
      end

      def admin_account(community_id)
        Maybe(PaypalAccountModel
            .where(person_id: nil, community_id: community_id)
            .eager_load(:order_permission)
            .first
          )
          .map { |model| Entity.paypal_account(model) }
          .or_else(nil)
      end
    end
  end
end