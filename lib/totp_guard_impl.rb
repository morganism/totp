#!/usr/bin/env ruby
#
# ––––– getting it wrong
# ruby totp_guard_impl.rb 437556
# code = 437556
# valid ? [false]
# $ echo $?
# 1    <-------- non zero ---
#
# ––––– getting it right
# $ ruby totp_guard_impl.rb 068779
# code = 068779
# valid ? [true]
# $ echo $?
# 0    <-------- zero -------
# ––––– qr
# ruby totp_guard_impl.rb qr
#
#
#

require_relative 'totp_guard'

HIDE_SHOW_FILE = "~/.totp_hide_show"
HIDE_OPT_RE = /^(hide)_?(\d+)/.freeze
SHOW_OPT_RE = /show/.freeze

  def hide_or_show h_or_s = nil
    path = File.expand_path(HIDE_SHOW_FILE)
    hide_or_show = h_or_s || File.read(path)

    the_match = hide_or_show&.match(HIDE_OPT_RE)
    if the_match
      puts "the #{the_match[2]}"
      shade=the_match[2]
      vshade=eval '033[38;5;#{shade}'
      hide
      print "#{vshade}"
    end
    if hide_or_show&.match?(SHOW_OPT_RE)
      show
      print "\033[0m"
    end
  end
  def hide
    puts "h"
    path = File.expand_path(HIDE_SHOW_FILE)
    File.write(path, :hide)
  end
  def show
    puts "s"
    path = File.expand_path(HIDE_SHOW_FILE)
    File.write(path, :show)
  end

  # Reads keypresses from the user including 2 and 3 escape character sequences.
  def read_char

    input = STDIN.getc.chr
    if input == "\e" then
      input << STDIN.read_nonblock(3) rescue nil
      input << STDIN.read_nonblock(2) rescue nil
    end
  ensure
    return input
  end

  def read_word 
    word = Array.new
    until word.length >= 6 
      word << read_char
    end
    word.join ''
  end
hide_or_show
code = ARGV[0] || read_word
#puts "code = #{code}"
hide_or_show code
print "code = #{code}\n"

   guard = TOTPGuard.new
   guard.add('alice@example.com', 'JBSWY3DPEHPK3PXP')
   guard.on_success { |r| logger.info "2FA ok: #{r.account}" }
   guard.on_failure { |r| logger.warn "2FA fail: #{r.account}" }
#   ok = guard.authenticate('alice@example.com', params[:code])
#
#   # Block form — result routed via yield:
#   guard.protect('alice@example.com', params[:code]) { |ok| ok ? serve : halt(401) }
#
#   # Bang form — raises on failure:
#   guard.authenticate!('alice@example.com', params[:code])
#
#   # DSL via const_missing:
   mogz_secret = 'HBTWGWHPDAUPSZOZACQ3CD57UBWOZE5A'
   mogz_account = 'Mogz'

   QR_OPT_RE = /qr/.freeze

   if code&.match?(QR_OPT_RE)
     #puts "OK"
     print "OK\n"
     TOTPGuard::QR.display_setup account: mogz_account, secret: mogz_secret
   else
     TOTPGuard::MyApp.add(mogz_account, mogz_secret)
     valid = TOTPGuard::MyApp.valid?(mogz_account, code)
     #puts "valid ? [#{valid}]"
     print "valid ? [#{valid}]\n"
     exit valid
   end
