-module(growl).
-compile(export_all).
-vsn(0.1). 
-author("Wade Mealing"). 


%% attempt at growl shown at http://growl.info/documentation/developer/protocol.php
%% This will likely be superseded by the new GNTP protocol.

registration_msg(ApplicationName,Password, Notifications) ->
	{ registration_msg, { ApplicationName, Password }, Notifications }.

add_notification_type(RegistrationMessage, NotificationType, EnabledByDefault) ->
	{ registration_msg, Details , ExistingNotifications }  = RegistrationMessage, 
	NewNotification =  [{ NotificationType, EnabledByDefault }], 
	{ registration_msg, Details, lists:append( ExistingNotifications, NewNotification) }.

notificationmsg(ApplicationName, Notification, Title, Description, Priority, Sticky, Password) -> 
	{ notification_msg, { ApplicationName, Password } , { Notification, Title, Description, Priority, Sticky, Password }}.

notificationbinary(NotificationMessage) ->
	{ NotificationString, _ } = NotificationMessage, 	
	Null = << 0 >>, 
	NotificationNameUTF8 =  xmerl_ucs:to_utf8(NotificationString),
	NotificationLength = string:len(NotificationNameUTF8),
	<< NotificationLength:8,(list_to_binary (NotificationNameUTF8))/binary, Null:1/binary >>. 

get_notifications_with_defaults(Notifications) ->
	SequencedNotifications = lists:zip( Notifications, lists:seq(1,length(Notifications))),
	% return a list of those that enabled=true.
	[ Seq || { { _ , IsEnabled }, Seq } <- SequencedNotifications , IsEnabled == true].

utf8_and_length(Word) ->
	{ xmerl_ucs:to_utf8(Word), string:len(xmerl_ucs:to_utf8(Word)) }.

sign_payload(Payload, Password) ->
	% FIXME: i think that this can be sent locally (127.0.0.1 with no pass ?)
	TempPayload = << Payload/binary , (list_to_binary(xmerl_ucs:to_utf8(Password)))/binary >> , 	
	PayloadChecksummed = << Payload/binary , (erlang:md5(TempPayload)):16/binary >> , 
	<< PayloadChecksummed/binary >>. 


registration_payload(RegistrationMessage, Cfg) ->

	{ registration_msg, { ApplicationName, Password } ,  Notifications  } = RegistrationMessage, 

	{ ApplicationNameUTF8, ApplicationNameUTF8Length } = utf8_and_length(ApplicationName),

	NotificationCount = length(Notifications),
	Defaults = get_notifications_with_defaults ( Notifications ),
	DefaultsCount = length(Defaults),

	NotificationsInBinary = lists:map(fun notificationbinary/1, Notifications), 

	{ok, ProtocolVersion}  = config:get(protocol_version, Cfg),
	{ok, TypeRegistration} = config:get(type_registration, Cfg),

	DefaultsSize = DefaultsCount - 1,

	Null = << 0 >>, 

	Payload = <<
				ProtocolVersion:8, 	% meh.
				TypeRegistration:8, 	% registration packet
				ApplicationNameUTF8Length:16,  	% 8 bits wide length of packet.
				NotificationCount:8,	% 8 bits wide, number of notifications. (nall)
				DefaultsCount:8,	% 8 bits wide, number of notifications enabled by default. (ndef) BUG.
				(list_to_binary(ApplicationNameUTF8))/binary, 	% Name of application in UTF8.
				Null:1/binary,					% app name needs to be null terminated, not sure why when we have the length set.
				(list_to_binary(NotificationsInBinary))/binary,	% notifications len and string.
				(list_to_binary(Defaults)):DefaultsSize/binary 
		      >> , 

	sign_payload(Payload, Password). 

notification_payload(NotificationMessage, Cfg) ->

	{ notification_msg, { ApplicationName, Password } , { Notification, Title, Description, Priority, Sticky, Password }} = NotificationMessage,
	{ ok, ProtocolVersion}  = config:get(protocol_version, Cfg),
	{ ok, TypeNotification}  = config:get(type_notification, Cfg),
	
	{ ApplicationNameUTF8 , ApplicationNameUTF8Length } = utf8_and_length( ApplicationName ), 
	{ NotificationUTF8, NotificationUTF8Length } = utf8_and_length( Notification ),
	{ DescriptionUTF8, DescriptionUTF8Length } = utf8_and_length( Description ),
	{ TitleUTF8, TitleUTF8Length } = utf8_and_length( Title ),

	% FIXME: build flags properly.		
	Flags = 0, 

	Payload = <<
				ProtocolVersion:8, 	% meh.
				TypeNotification:8, 	% registration packet
				Flags:16, 
				NotificationUTF8Length:16,
				TitleUTF8Length:16,
				DescriptionUTF8Length:16, 
				ApplicationNameUTF8Length:16,
				(list_to_binary(NotificationUTF8))/binary, 
				(list_to_binary(TitleUTF8))/binary, 
				(list_to_binary(DescriptionUTF8))/binary,
				(list_to_binary(ApplicationNameUTF8))/binary 	% Name of application in UTF8.
		      >>, 

	sign_payload(Payload, Password). 


send_packet( Message ) -> 
	{ok, Cfg} = config:read("growl.cfg"), 

	case erlang:element(1, Message) of
		registration_msg -> 
			Payload = registration_payload(Message, Cfg);
		notification_msg ->
			Payload = notification_payload(Message, Cfg);
		_ ->	
			io:format("CRAAAAAZY MATCH! ~n"), 
			Payload = { error, "Unknown Message Type" }
	end,


	{ok, UdpPort}  = config:get(udp_port, Cfg),
	{ok, HostName}  = config:get(host, Cfg),

	{ok, Socket} = gen_udp:open(49753, [binary]),
	ok = gen_udp:send(Socket, HostName , UdpPort, Payload),

	% Close immediately.
	gen_udp:close(Socket),

	% report we are done. 
	ok. 

test() ->
	AppName = "ErlangDemo",
	Password = "test",
	RegMsg1 = registration_msg(AppName, Password, []),
	RegMsg2 = add_notification_type( RegMsg1, "Notification1", true),
	RegMsg3 = add_notification_type( RegMsg2, "Notification2", true),
	RegMsg4 = add_notification_type( RegMsg3, "Notification3", true),
	RegMsgFinal = add_notification_type( RegMsg4, "Notification4", false),
	send_packet(RegMsgFinal),

	NotMesg2 = notificationmsg(AppName, "Notification1", 
					    "This is the title",
					    "This is the description", 
					    "Priority",
					    "Sticky",
					    Password ),

	send_packet(NotMesg2), 

	io:format("Test complete.~n").


