# -*- coding: UTF-8 -*-
# Be sure to restart your server when you modify this file.

LOCALES_DIRECTORY = Rails.root.to_s + '/config/locales/'

LANGUAGES = {
  'Deutsch' => 'de',
  'Dutch' => 'nl',
  'English(AU)' => 'en_AU',
  'English(US)' => 'en',
  'English(CA)' => 'en_CA',
  'English(GB)' => 'en_GB',
  'English(NZ)' => 'en_NZ',
  'English(ZA)' => 'en_ZA',
  "Français(CA)" => 'fr_CA',
  'Italiano' => 'it',
  'Português(BR)' => 'pt_BR',
  'Svenska' => 'sv'
}

I18n.enforce_available_locales = true
begin
  opt = Option.first
  I18n.fallbacks = true
  I18n.default_locale = :en
  I18n.locale = opt.locale
rescue
  I18n.default_locale = :en
  I18n.locale = :en
end

