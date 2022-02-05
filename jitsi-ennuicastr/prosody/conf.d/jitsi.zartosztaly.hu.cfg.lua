VirtualHost "jitsi.castr.zartosztaly.hu"
    authentication = "jitsi-anonymous"

    ssl = {
        key = "/config/certs/jitsi.castr.zartosztaly.hu.key";
        certificate = "/config/certs/jitsi.castr.zartosztaly.hu.crt";
    }
    modules_enabled = {
        "bosh";
        "websocket";
        "smacks"; -- XEP-0198: Stream Management
        "pubsub";
        "ping";
        "speakerstats";
        "conference_duration";
        "muc_lobby_rooms";
        "muc_breakout_rooms";
        "av_moderation";
    }

    main_muc = "muc.meet.jitsi"
    lobby_muc = "lobby.meet.jitsi"
    muc_lobby_whitelist = { "recorder.meet.jitsi" }
    breakout_rooms_muc = "breakout.meet.jitsi"
    speakerstats_component = "speakerstats.meet.jitsi"
    conference_duration_component = "conferenceduration.meet.jitsi"
    av_moderation_component = "avmoderation.meet.jitsi"
    c2s_require_encryption = false
