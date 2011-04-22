require 'rubygems'
require 'mechanize'
require 'nokogiri'
Mechanize.html_parser = Nokogiri::HTML
require 'nkf'

module Cybozu
  module Office
    class Schedule
      def initialize(url, uid, gid, password)
        @pages = {
          'SCHEDULE_INDEX' => '?page=ScheduleIndex',
          'SCHEDULE_MONTH' => '?page=ScheduleUserMonth',
          'SCHEDULE_GET' => '?page=ScheduleView',
          'SCHEDULE_POST' => '?page=ScheduleEntry',
          'SCHEDULE_PUT' => '?page=ScheduleModify',
          'SCHEDULE_DELETE' => '?page=ScheduleDelete'
        }

        @url = url
        @uid = uid
        @gid = gid
        @password = password

        @version = nil

        @agent = Mechanize.new
        @agent.post_connect_hooks << Proc.new do |params|
          if %r|text| =~ params[:response]["Content-Type"]
            params[:response_body] = NKF.nkf("-wm0",params[:response_body])
            params[:response_body].gsub(/<meta[^>]*>/) do |meta|
              meta.sub(/Shift_JIS|SJIS|EUC-JP/i,"UTF-8")
            end
            params[:response]["Content-Type"]="text/html; charset=utf-8"
          end
        end
      end

      def login
        @agent.user_agent_alias = 'Windows Mozilla'
        @agent.get(@url)
        @agent.page.parser.encoding = 'CP932'

        version_regexp = Regexp.new("^.* Office Version ([^\(]+)\(.+\)$")
        @agent.page.search('font').each{|font|
          if font.children.to_s =~ version_regexp
            @version = $1.to_f
          end
        }

        @agent.page.form_with(:name => 'LoginForm'){|login_form|
          login_form['_ID'] = @uid
          login_form['Password'] = @password
          login_form['Submit'] = NKF.nkf("-w", "ログイン")
          @agent.submit(login_form)
          if NKF.nkf("-w", @agent.page.title.to_s) == 'トップページ - サイボウズ(R) Office'
            return true
          end
          return false
        }
        return false
      end

      def logout
      end

      def get_events(date_b, date_e)
        ym_b = (date_b.to_i/100).to_i
        ym_e = (date_e.to_i/100).to_i
        target_ym = ym_b
        events = []
        while target_ym <= ym_e
          target_year = (target_ym/100).to_i
          target_month = (target_ym%100).to_i
          @agent.get("#{@url}#{@pages['SCHEDULE_MONTH']}&UID=#{@uid}&GID=#{@gid}&Date=da.#{target_year}.#{target_month}.1")
          @agent.page.parser.encoding = 'CP932'
          @agent.page.links.each{|link|
            schedule_view_regexp = Regexp.new(".*#{@pages['SCHEDULE_GET']}&(UID|uid)=#{@uid}&(GID|gid)=#{@gid}&(Date|date)=da.([0-9]{4})\.([0-9]{1,2})\.([0-9]{1,2})&BDate=da.([0-9\.]+)&sEID=([0-9]+)&(CP|cp)=sm")
            if link.uri.to_s =~ schedule_view_regexp
              event_year = $4.to_i
              event_month = $5.to_i
              event_day = $6.to_i
              event_id = $8.to_i
              event_date = event_year * 10000 + event_month * 100 + event_day
              event_ym = event_year * 100 + event_month
              if event_date.to_i >= date_b.to_i && event_date.to_i <= date_e.to_i && event_ym == target_ym
                event = Cybozu::Office::Event.new
                event.set_eid(event_id)
                event.set_year(event_year)
                event.set_month(event_month)
                event.set_day(event_day)
                @agent.get("#{@url}#{@pages['SCHEDULE_PUT']}&UID=#{@uid}&GID=#{@gid}&Date=da.#{event_year}.#{event_month}.#{event_day}&BDate=da.#{event_year}.#{event_month}.#{event_day}&sEID=#{event_id}&cp=sgmv")
                @agent.page.parser.encoding = 'CP932'
                @agent.page.form_with(:name => 'ScheduleModify'){|put_form|
                  event.set_title(NKF.nkf("-w", put_form.field_with(:name => 'Detail').value))
                  event.set_hour_b(put_form.field_with(:name => 'SetTime.Hour').value)
                  event.set_minute_b(put_form.field_with(:name => 'SetTime.Minute').value)
                  event.set_hour_e(put_form.field_with(:name => 'EndTime.Hour').value)
                  event.set_minute_e(put_form.field_with(:name => 'EndTime.Minute').value)
                  events.push(event)
                }
              end
            end
          }
          target_ym += 1
          if (target_ym%100).to_i == 13
            target_ym += 88
          end
        end
        return events
      end

      def post_event(event)
        @agent.get("#{@url}#{@pages['SCHEDULE_POST']}&UID=#{@uid}&GID=#{@gid}&Date=da.#{event.year}.#{event.month}.#{event.day}&BDate=da.#{event.year}.#{event.month}.#{event.day}&cp=sm")
        @agent.page.parser.encoding = 'CP932'
        @agent.page.form_with(:name => 'ScheduleEntry'){|post_form|
          post_form['Detail'] = NKF.nkf("-w", event.title)
          post_form.field_with(:name => 'SetTime.Hour').value = event.hour_b
          post_form.field_with(:name => 'SetTime.Minute').value = event.minute_b
          post_form.field_with(:name => 'EndTime.Hour').value = event.hour_e
          post_form.field_with(:name => 'EndTime.Minute').value = event.minute_e
          if @version.to_i == 6
            post_form.field_with(:name => 'sUID').value = @uid
          end
          post_form['Entry'] = NKF.nkf("-w", "登録する")
          @agent.submit(post_form)
        }
      end

      def delete_event(event)
        @agent.get("#{@url}#{@pages['SCHEDULE_DELETE']}&UID=#{@uid}&GID=#{@gid}&Date=da.#{event.year}.#{event.month}.#{event.day}&BDate=da.#{event.year}.#{event.month}.#{event.day}&sEID=#{event.eid}&cp=smv")
        @agent.page.parser.encoding = 'CP932'
        if NKF.nkf("-w", @agent.page.title.to_s) == '予定の削除 - サイボウズ(R) Office'
          @agent.page.form_with(:name => 'ScheduleDelete'){|delete_form|
            delete_form['Yes'] = NKF.nkf("-w", "はい")
            @agent.submit(delete_form)
          }
        end
      end
    end

    class Event
      def initialize
        @eid = ''
        @title = ''
        @year = ''
        @month =''
        @day = ''
        @hour_b = ''
        @minute_b = ''
        @hour_e = ''
        @minute_e = ''
      end

      def eid
        return @eid
      end
      def set_eid(int)
        @eid = int.to_i
        return @self
      end

      def title
        return @title
      end
      def set_title(str)
        @title = str.to_s
        return @self
      end

      def year
        return @year
      end
      def set_year(str)
        @year = str.to_s
        return @self
      end

      def month
        return @month
      end
      def set_month(str)
        @month = str.to_s
        return @self
      end

      def day
        return @day
      end
      def set_day(str)
        @day = str.to_s
        return @self
      end

      def hour_b
        return @hour_b
      end
      def set_hour_b(str)
        @hour_b = str.to_s
        return @self
      end

      def minute_b
        return @minute_b
      end
      def set_minute_b(str)
        @minute_b = str.to_s
        return @self
      end

      def hour_e
        return @hour_e
      end
      def set_hour_e(str)
        @hour_e = str.to_s
        return @self
      end

      def minute_e
        return @minute_e
      end
      def set_minute_e(str)
        @minute_e = str.to_s
        return @self
      end
    end
  end
end
