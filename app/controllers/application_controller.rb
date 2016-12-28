# -*- encoding : utf-8 -*-
require 'uservoice_sso'

class ApplicationController < ActionController::Base
  layout :use_catarse_boostrap
  protect_from_forgery

  rescue_from CanCan::Unauthorized do |exception|
    session[:return_to] = request.env['REQUEST_URI']
    message = exception.message 

    if current_user.nil?
      redirect_to new_user_session_path, alert: I18n.t('devise.failure.unauthenticated')
    elsif request.env["HTTP_REFERER"]
      redirect_to :back, alert: message 
    else
      redirect_to root_path, alert: message
    end
  end

  helper_method :namespace, :fb_admins, :render_facebook_sdk, :render_facebook_like, :render_twitter, :display_uservoice_sso, :blog_posts, :embedded_svg, :inside_channel?, :test_environment?, :to_usd, :to_cop
  
  before_filter :set_locale

  # TODO: Change this way to get the opendata
  before_filter do
    @fb_admins = [100000428222603, 547955110]
  end

  # We use this method only to make stubing easier 
  # and remove FB templates from acceptance tests
  def render_facebook_sdk
    render_to_string(partial: 'layouts/facebook_sdk').html_safe
  end

  def render_twitter options={}
    render_to_string(partial: 'layouts/twitter', locals: options).html_safe
  end

  def render_facebook_like options={}
    render_to_string(partial: 'layouts/facebook_like', locals: options).html_safe
  end

  def display_uservoice_sso
    if current_user and ::Configuration[:uservoice_subdomain] and ::Configuration[:uservoice_sso_key]
      Uservoice::Token.generate({
        guid: current_user.id, email: current_user.email, display_name: current_user.display_name,
        url: user_url(current_user), avatar_url: current_user.display_image
      })
    end
  end

  def inside_channel?
    not (request.subdomain.blank? || request.subdomain == 'lbm2-cesvald')
  end
  
  def test_environment?
    request.original_url.start_with?('http://s22.org')
  end
  
  def to_usd(amount)
    conversion = ::Configuration[:paypal_conversion].to_f
    (amount / conversion).round(0)
  end
  
  def to_cop(amount)
    conversion = ::Configuration[:paypal_conversion].to_f
    ( amount * conversion ).round(0)
  end
  
  private
  
  def fb_admins
    @fb_admins.join(',')
  end

  def fb_admins_add(ids)
    case ids.class
    when Array
      ids.each {|id| @fb_admins << ids.to_i}
    else
      @fb_admins << ids.to_i
    end
  end

  def embedded_svg filename, options={}
    file = File.read(Rails.root.join('app', 'assets', 'images', filename))
    doc = Nokogiri::HTML::DocumentFragment.parse file
    svg = doc.at_css 'svg'
    if options[:class].present?
      svg['class'] = options[:class]
    end
    svg.to_html.html_safe
  end

  def namespace
    names = self.class.to_s.split('::')
    return "null" if names.length < 2
    names[0..(names.length-2)].map(&:downcase).join('_')
  end

  def set_locale
    if test_environment?
      if !current_user
        #sign_in User.find_by_email("maria.hoyos@fundacioncapital.org"), event: :authentication, store: true
        if not ::Configuration[:test_user_email].blank?
          sign_in User.find_by_email(::Configuration[:test_user_email]), event: :authentication, store: true
        end
      end
    end
    if params[:locale]
      I18n.locale = params[:locale]
      current_user.update_attribute :locale, params[:locale] if current_user && params[:locale] != current_user.locale
    elsif request.method == "GET"
      new_locale = (current_user.locale if current_user) || I18n.default_locale
      begin
        return redirect_to params.merge(locale: new_locale, only_path: true)
      rescue ActionController::RoutingError 
        logger.info "Could not redirect with params #{params.inspect} in set_locale"
      end
    end
  end

  def use_catarse_boostrap
    devise_controller? ? 'catarse_bootstrap' : 'application'
  end

  def redirect_back_or_default(default)
    redirect_to(session[:return_to] || default)
    session[:return_to] = nil
  end

  def after_sign_in_path_for(resource_or_scope)
    return_to = session[:return_to]
    session[:return_to] = nil
    (return_to || root_path)
  end

  def render_404
    render file: "#{Rails.root}/public/404.html", status: 404, layout: false
  end

  def blog_posts
    Blog.fetch_last_posts.inject([]) do |total,item|
      total << item if total.size < 2
      total
    end
  rescue
    []
  end

  def authenticate_api(check_api_user = false, token = nil)
    user = nil
    authenticate_or_request_with_http_token do |token, options|
      user = authenticate_token(token, check_api_user)
    end
    user
  end

  def authenticate_token(token, check_api_user = false)
    api_key = ApiKey.not_expired.find_by_access_token(token)
    if api_key
      if (check_api_user && api_key.user.api?) || (!check_api_user)
        sign_in(:user, api_key.user)
      else
        nil
      end
    else
      nil
    end
  end

end
