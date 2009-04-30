# encoding: utf-8
#--
#   Copyright (C) 2009 Nokia Corporation and/or its subsidiary(-ies)
#   Copyright (C) 2007, 2008 Johan Sørensen <johan@johansorensen.com>
#   Copyright (C) 2008 David A. Cuadrado <krawek@gmail.com>
#   Copyright (C) 2008 Tor Arne Vestbø <tavestbo@trolltech.com>
#   Copyright (C) 2009 Fabio Akita <fabio.akita@gmail.com>
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Affero General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Affero General Public License for more details.
#
#   You should have received a copy of the GNU Affero General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#++

class UsersController < ApplicationController
  skip_before_filter :public_and_logged_in, :only => [
    :activate, :forgot_password, :forgot_password_create, :reset_password 
  ]
  before_filter :login_required, :only => [:edit, :update, :password, :update_password, :avatar]
  before_filter :find_user, :only => [:show, :edit, :update, :password, :update_password, :avatar]
  before_filter :require_current_user, :only => [:edit, :update, :password, :update_password, :avatar]
  before_filter :require_identity_url_in_session, :only => [:openid_build, :openid_create]
  before_filter :require_public_user, :only => :show
  renders_in_global_context
  ssl_required :new, :create, :edit, :update, :password, :forgot_password_create, 
                :forgot_password, :update_password, :reset_password, :avatar
 
  # render new.rhtml
  def new
  end
  
  def show
    @projects = @user.projects.find(:all, :include => [:tags, { :repositories => :project }])
    @repositories = @user.commit_repositories
    @events = @user.events.top.paginate(:all, 
      :page => params[:page],
      :order => "events.created_at desc", 
      :include => [:user, :project])
    
    @commits_last_week = @user.events.count(:all, 
      :conditions => ["created_at > ? AND action = ?", 7.days.ago, Action::COMMIT])
    @atom_auto_discovery_url = feed_user_path(@user, :format => :atom)
    
    respond_to do |format|
      format.html { }
      format.atom { redirect_to feed_user_path(@user, :format => :atom) }
    end
  end
  
  def feed
    @user = User.find_by_login!(params[:id])
    @events = @user.events.find(:all, :order => "events.created_at desc", 
      :include => [:user, :project], :limit => 30)
    respond_to do |format|
      format.html { redirect_to user_path(@user) }
      format.atom { }
    end
  end

  def create
    @user = User.new(params[:user])
    @user.login = params[:user][:login]
    @user.save!    
    if !@user.terms_of_use.blank?
      @user.accept_terms!
    end
    flash[:success] = I18n.t "users_controller.create_notice"
    redirect_to root_path
  rescue ActiveRecord::RecordInvalid
    render :action => 'new'
  end

  def activate
    if user = User.find_by_activation_code(params[:activation_code])
      self.current_user = user
      if logged_in? && !current_user.activated?
        current_user.activate
        flash[:notice] = I18n.t "users_controller.activate_notice"
      end
    else
      flash[:error] = I18n.t "users_controller.activate_error"
    end
    redirect_back_or_default('/')
  end
  
  def forgot_password
  end
    
  def forgot_password_create
    if params[:user] && user = User.find_by_email(params[:user][:email])
      password_key = user.forgot_password!
      Mailer.deliver_forgotten_password(user, password_key)
      flash[:success] = "A password confirmation link has been sent to your email address"
      redirect_to(root_path)
    else
      flash[:error] = I18n.t "users_controller.reset_password_error"
      redirect_to forgot_password_users_path
    end
  end
  
  def reset_password
    @user = User.find_by_password_key(params[:token])
    unless @user
      flash[:error] = I18n.t "users_controller.reset_password_error"
      redirect_to forgot_password_users_path
      return
    end
    
    if request.put?
      @user.password = params[:user][:password]
      @user.password_confirmation = params[:user][:password_confirmation]
      if @user.save
        flash[:success] = "Password updated"
        redirect_to(new_sessions_path)
      end
    end
  end

  def edit
    @user = current_user
  end

  def update
    @user = current_user
    @user.attributes = params[:user]
    if current_user.save
      flash[:success] = "Your account details were updated"
      redirect_to user_path
    else
      render :action => "edit"
    end
  end

  def password
    @user = current_user
  end

  def update_password
    @user = current_user
    if User.authenticate(current_user.email, params[:user][:current_password]) || @user.is_openid_only?
      @user.password = params[:user][:password]
      @user.password_confirmation = params[:user][:password_confirmation]
      if @user.save
        flash[:success] = "Your password has been changed"
        redirect_to user_path(@user)
      else
        render :action => "password"
      end
    else
      flash[:error] = "Your current password doesn't seem to match the one your supplied"
      render :action => "password"
    end
  end
  
  def openid_build
    @user = User.new(:identity_url => session[:openid_url], :email => session[:openid_email], :login => session[:openid_nickname], :fullname => session[:openid_fullname])
  end
  
  def openid_create
    @user = User.new(params[:user])
    @user.login = params[:user][:login]
    @user.identity_url = session[:openid_url]
    if @user.save
      if !@user.terms_of_use.blank?
        @user.accept_terms!
      end
      @user.activate
      [:openid_url, :openid_email, :openid_nickname, :openid_fullname].each do |k|
        session.delete(k)
      end
      self.current_user = @user
      redirect_back_or_default '/'
    else
      render :action => 'openid_build'
    end
  end
  
  # DELETE avatar
  def avatar
    @user.avatar.destroy
    @user.save
    flash[:success] = "You profile image was deleted"
    redirect_to user_path
  end
  
  protected
    def find_user
      @user = User.find_by_login!(params[:id])
    end
    
    def require_identity_url_in_session
      if session[:openid_url].blank?
        redirect_to :action => "new" and return
      end
    end
    
    def require_public_user
      unless @user.public?
        flash[:notice] = "This user profile is not public"
        redirect_back_or_default root_path
      end
    end
end
