require 'curb'
require 'eventmachine'
require 'em-eventsource'
require 'json'
require 'time'
require 'pp'
require 'active_support'
require 'open3'

$invoked_at = Time.now

$say = "say" # add params here if needed

$max_delay = 10
$min_delay = 2

GlobalEvents = {}
$global_event_keys = []
$last_global_announce = -1
$last_global_announce_time = Time.now
$season = nil
$day = nil

$message_allocation_seconds = 12

$score_frequency = 60

$announce_freq = 20
$announce_thread = nil
$game_thread = nil

$last_update_time = Time.now

LastScoreAnnouncedAtByHome = Hash.new{ $invoked_at }
LastMessageByGame = {}
LastThreadByVoice = {}

def voice_for_home(team)
  case team
  when "Lovers"
    "Ralph"
  when "Moist Talkers"
    "Vicki"
  when "Tigers"
    "Daniel"
  when "Dale"
    "Kate"
  when "Flowers"
    "Lee"
  when /^[WM]ild [WM]ings$/
    "Oliver"
  when "Tacos"
    "Karen"
  when "Millennials"
    "Alex"
  when "Pies"
    "Allison"
  when "Crabs"
    "Moira"
  when "Jazz Hands"
    "Veena"
  when "Firefighters"
    "Fred"
  when "Spies"
    "Tessa"
  when "Sunbeams"
    "Serena"
  when "Garages"
    "Tom"
  when "Breath Mints"
    "Agnes"
  when "Shoe Thieves"
    "Susan"
  when "Magic"
    "Victoria"
  when "Steaks"
    "Bruce"
  when "Fridays"
    "Ava"
  else
    "Boing"
  end
end

def voice_for_global(key)
  case(key)
  when "commissioner_parker"
    'Zarvox'
  when "bigger_machines"
    'Cellos'
  when 'is_it_the_same'
    'Bad News'
  when 'peanuts_eaten'
    'Pipe Organ'
  when 'the_birds'
    'Hysterical'
  when 'darkness_forecast'
    'Trinoids'
  when 'current_labour'
    'Good News'
  when 'SHELLING'
    'Bells'
  when 'peanuts_are_everywhere'
    'Deranged'
  when 'in_memoriam'
    'Pipe Organ'
  when 'event'
    'Boing'
  else
    "Whisper"
  end
end

def refresh_global_events
  global_events_json = Curl::Easy.perform("https://www.blaseball.com/database/globalEvents").body_str
  global_events = JSON.parse(global_events_json)

  global_events.each do |event|
    id = event["id"]
    GlobalEvents[id] = {msg: event["msg"], expire: event["expire"] && Time.parse(event["expire"])}
  end

  GlobalEvents.keys.each do |key|
    if GlobalEvents[key][:expire] && GlobalEvents[key][:expire] < Time.now
      GlobalEvents.delete key
    end
  end
  $global_event_keys = GlobalEvents.keys.shuffle
end

def message_wait_time
  if ($active_game_count > 0)
    $message_allocation_seconds.to_f / $active_game_count
  else
    $message_allocation_seconds
  end
end


def random_blaseball
  val = rand
  if val < 0.1
    return "blaseball"
  elsif val < 0.2
    return "blaisball"
  elsif val < 0.3
    return "blaiceball"
  elsif val < 0.4
    return "blassball"
  elsif val < 0.5
    return "blasball"
  elsif val < 0.7
    return "blais ball"
  elsif val < 0.6
    return "blaiseball"
  elsif val < 0.7
    return "blayzball"
  else
    return "blazeball"
  end
end

def fix_pronounce(message)
  return message\
    .gsub(/blaseball/i){ random_blaseball }
    .gsub(/McBlase/i, "McBlaze")
    .gsub(/\bII\b/i, "the second")
    .gsub(/\bIII\b/i, "the third")
    .gsub(/\bWHO\b/, "Who")
    .gsub(/\bStu\b/, "Stew")
    .gsub(/\s-Infinity\b/, " negative Infinity")
    .gsub(/\bSpies\b/i, "spies")
    .gsub(/(\d)-(\d)/, "\\1 and \\2")
    .gsub(/\b0(\s)/, "Oh\\1")
end

def say(voice, msg)
  lastthread = LastThreadByVoice[voice]
  thread = Thread.new do
    if lastthread && lastthread.status
      lastthread.join
    end
    system( "#{$say} -v #{voice.inspect} #{msg.inspect}" )
  end
  LastThreadByVoice[voice] = thread
  return thread
end

def announce_day
  Thread.new do
    voice = "Zarvox"
    msg = "Season #{$season} Day #{$day}"
    puts "=== #{msg} ==="
    start = Time.now
    # take over both channels
    if $announce_thread && $announce_thread.status
      $announce_thread.join
    end
    if $game_thread && $game_thread.status
      $game_thread.join
    end
    $game_thread = $announce_thread = say voice, msg
    $last_global_announce_time = Time.now
  end
end

def announce_global_event
  return if Time.now - $last_global_announce_time < $announce_freq + $announce_freq * rand
  return if $announce_thread && $announce_thread.status

  Thread.new do
    $last_global_announce_time = Time.now

    announce_event_number = $last_global_announce + 1
    if announce_event_number >= GlobalEvents.keys.length
      announce_event_number = 0
      $global_event_keys = GlobalEvents.keys.shuffle
    end
    $last_global_announce = announce_event_number
    key = $global_event_keys[announce_event_number]
    return unless key

    event = GlobalEvents[key][:msg]

    if key =~ /........-....-....-....-............/
      key = "event"
    end

    voice = voice_for_global(key)
    puts "#{key}: #{event}"
    msg = fix_pronounce(event)

    start = Time.now
    $announce_thread = say voice, msg
    $last_global_announce_time = Time.now
  end
end

def pronounce_score(score)
  case(score)
  when 0
    return "O"
  else
    return score
  end
end

def handle_game(game)
  home = game["homeTeamNickname"]
  away = game["awayTeamNickname"]
  voice = voice_for_home(home)
  top_or_bottom = game["topOfInning"] ? "top" : "bottom"
  inning = ActiveSupport::Inflector.ordinalize(game["inning"] + 1)
  at_bat = game["homeBatterName"] || game["awayBatterName"]
  last_update = game["lastUpdate"]

  score_messsage = "#{home} #{pronounce_score(game["homeScore"])} #{away} #{pronounce_score(game["awayScore"])}, "

  msg = ""
  if game["gameComplete"]
    msg += score_messsage
    msg += last_update + " "
  else
    #msg = "The #{game["homeTeamName"]} versus the #{game["awayTeamName"]}, "
    #msg += "#{home} #{pronounce_score(game["homeScore"])} #{away} #{pronounce_score(game["awayScore"])}, "
    #msg += "#{top_or_bottom} of the #{inning}, "
    #msg += "#{game["atBatBalls"]} balls #{game["atBatStrikes"]} strikes, "
    msg += last_update + " "

    if msg =~ /^Top of/ || msg =~ /^Bottom of/
      pitcher = !game["topOfInning"] ? game["awayPitcherName"] : game["homePitcherName"]
      pitcherTeam = !game["topOfInning"] ? game["awayTeamNickname"] : game["homeTeamName"]
      msg += "#{pitcher} is pitching for the #{pitcherTeam}. "
    end

    if msg =~ /\bscores\b/ || msg =~ /\bhome run\b/
      msg += score_messsage
    end
  end

  if (msg == LastMessageByGame[game["id"]])
    return
  end

  LastMessageByGame[game["id"]] = msg

  queued = Time.now

  action = Proc.new do
    active = Time.now
    delayed = active - queued
    if (delayed > $max_delay)
      $message_allocation_seconds *= 0.99
    elsif (delayed < $min_delay)
      $message_allocation_seconds += 0.1
    end

    if $active_game_count == 1
      # last game gets every message
      say(voice, fix_pronounce(msg))
    else
      # usually these are too chatty
      case msg
      when /^Ball. \d-\d\s*$/, /^Foul Ball. \d-\d\s*$/, /^Strike, looking\. \d-\d\s*$/, /^Strike, swinging\. \d-\d\s*$/
        nil
      when / batting for the /
        nil
      else
        say(voice, fix_pronounce(msg))
      end
    end&.join
  end

  wrapped_action = Proc.new do
    st = Time.now
    thr = Thread.new(&action)
    while Time.now - st < message_wait_time && thr.status
      sleep 0.05
    end
  end

  puts "#{home.upcase}/#{away.upcase}: #{msg}"
  if $game_thread && $game_thread.status
    game_thread = $game_thread
    $game_thread = Thread.new do
      game_thread.join
      wrapped_action[]
    end
  else
    $game_thread = Thread.new(&wrapped_action)
  end
end

def handle_event_message(message)
  json = JSON.parse( message.sub(/^data: /, "") ) rescue nil
  return unless json
  puts
  $last_update_time = Time.now
  if (json["value"]["games"]["sim"]["day"] rescue nil)
    if $day != json["value"]["games"]["sim"]["day"] + 1
      $day = json["value"]["games"]["sim"]["day"] + 1
    end
  end
  if (json["value"]["games"]["sim"]["season"] rescue nil)
    if $season != json["value"]["games"]["sim"]["season"] + 1
      $season = json["value"]["games"]["sim"]["season"] + 1
      announce_day
    end
  end
  games = ((json["value"]["games"]["schedule"] rescue nil) || [])
  $active_game_count = games.count { |game| !game["gameComplete"] }
  games.each do |game|
    handle_game(game)
  end
end

def handle_event_stream(body)
  return body unless body.match /\n/
  message, rest = body.split("\n",2)
  handle_event_message(message)
  return rest
rescue
  return ""
end

loop do
  refresh_global_events
  http = EM::HttpRequest.new("https://www.blaseball.com/events/streamData", :keepalive => true, :connect_timeout => 5, :inactivity_timeout => 10, tls: {verify_peer: true})
  stream = nil
  EventMachine.run do
    timer = EventMachine::PeriodicTimer.new(2) do
      announce_global_event
    end

    timer = EventMachine::PeriodicTimer.new(60) do
      refresh_global_events
    end

    timer = EventMachine::PeriodicTimer.new(1) do
      if stream && !stream.finished?
        nil
      else
        stream = http.get({'accept' => 'application/json'})
        body = ""
        stream.errback do
          stream = nil
        end
        stream.stream do |data|
          body << data
          body = handle_event_stream(body)
        end
      end
    end

  end
end
