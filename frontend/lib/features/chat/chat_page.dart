import 'dart:async';
import 'dart:convert';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_storage.dart';
import '../../services/api_config.dart';
import '../../services/chat_api.dart';
import '../../services/chat_navigation.dart';

String _relativeTime(dynamic value) {
  if (value == null) return '';
  final timestamp = DateTime.tryParse('$value')?.toLocal();
  if (timestamp == null) return '';
  final difference = DateTime.now().difference(timestamp);
  if (difference.inMinutes < 1) return 'Now';
  if (difference.inHours < 1) return '${difference.inMinutes}m';
  if (difference.inDays < 1) return '${difference.inHours}h';
  if (difference.inDays == 1) return 'Yesterday';
  if (difference.inDays < 7) return DateFormat.E().format(timestamp);
  return DateFormat.MMMd().format(timestamp);
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _composer = TextEditingController();
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _messages = [];
  int? _conversationId;
  int? _myId;
  String _name = '';
  bool _loading = true;
  bool _sending = false;
  bool _detailsOpen = false;
  bool _threadLoading = false;
  String? _threadError;
  Timer? _refreshTimer;
  bool _refreshInFlight = false;

  @override
  void initState() {
    super.initState();
    _load();
    // The backend stores messages, but this page does not keep a Socket.IO
    // connection. Polling keeps both open chat windows in sync immediately.
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _composer.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_refreshInFlight || _sending) return;
    _refreshInFlight = true;
    try {
      final conversations = await ChatApi.conversations();
      if (!mounted) return;
      setState(() => _conversations = conversations);

      final id = _conversationId;
      if (id != null) await _refreshThread();
    } catch (_) {
      // A short temporary network failure should not disrupt an open chat.
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _load() async {
    final raw = await AuthStorage.getString('user_data');
    if (raw != null) {
      try { _myId = (jsonDecode(raw) as Map)['id'] as int?; } catch (_) {}
    }
    try {
      _conversations = await ChatApi.conversations();
      final pendingId = ChatNavigation.takePendingConversationId();
      if (pendingId != null) {
        for (final item in _conversations) {
          if (item['id'] == pendingId) { await _select(item); break; }
        }
      }
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _select(Map<String, dynamic> item) async {
    final id = item['id'] as int;
    setState(() { _conversationId = id; _name = item['other_name']?.toString() ?? 'Conversation'; _messages = []; _threadLoading = true; _threadError = null; });
    try {
      final data = await ChatApi.messages(id);
      if (!mounted || id != _conversationId) return;
      setState(() => _messages = List<Map<String, dynamic>>.from(data['items'] as List));
      await _markMessagesDelivered(id);
      if (_messages.isNotEmpty) await ChatApi.read(id, _messages.last['id'] as int);
    } catch (error) {
      if (mounted && id == _conversationId) setState(() => _threadError = '$error');
    } finally {
      if (mounted && id == _conversationId) setState(() => _threadLoading = false);
    }
  }

  Future<void> _refreshThread() async {
    final id = _conversationId;
    if (id == null) return;
    try {
      final data = await ChatApi.messages(id);
      if (!mounted || id != _conversationId) return;
      setState(() { _messages = List<Map<String, dynamic>>.from(data['items'] as List); _threadError = null; });
      await _markMessagesDelivered(id);
      if (_messages.isNotEmpty) await ChatApi.read(id, _messages.last['id'] as int);
    } catch (error) {
      if (mounted) setState(() => _threadError = '$error');
    }
  }

  Future<void> _markMessagesDelivered(int conversationId) async {
    final received = _messages
        .where((message) => message['sender_user_id'] != null && message['sender_user_id'] != _myId)
        .map((message) => message['id'] as int)
        .fold<int?>(null, (latest, id) => latest == null || id > latest ? id : latest);
    if (received == null) return;
    try { await ChatApi.delivered(conversationId, received); } catch (_) {}
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (_conversationId == null || body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try { _composer.clear(); await ChatApi.send(_conversationId!, body); await _refreshThread(); await _load(); }
    finally { if (mounted) setState(() => _sending = false); }
  }

  Future<void> _attach() async {
    if (_conversationId == null || _sending) return;
    final result = await FilePicker.platform.pickFiles(withData: true, type: FileType.custom, allowedExtensions: const ['jpg','jpeg','png','pdf','docx','xlsx','pptx','mp3','m4a','wav']);
    final file = result?.files.single;
    if (file?.bytes == null) return;
    setState(() => _sending = true);
    try { await ChatApi.upload(_conversationId!, file!.bytes!, file.name); await _refreshThread(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    finally { if (mounted) setState(() => _sending = false); }
  }

  Future<void> _startConversation() async {
    try {
      final people = await ChatApi.people();
      if (!mounted) return;
      final person = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: 460,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: Text('New message', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                Expanded(
                  child: people.isEmpty
                      ? const Center(child: Text('No people are available to message.'))
                      : ListView.separated(
                          itemCount: people.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = people[index];
                            final name = '${item['name'] ?? 'Employee'}';
                            return ListTile(
                              leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
                              title: Text(name),
                              subtitle: Text('${item['role'] ?? 'Employee'}'),
                              onTap: () => Navigator.pop(context, item),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
      if (person == null || !mounted) return;
      final conversationId = await ChatApi.direct(person['id'] as int);
      await _load();
      if (!mounted) return;
      final conversation = _conversations.cast<Map<String, dynamic>>().firstWhere(
            (item) => item['id'] == conversationId,
            orElse: () => <String, dynamic>{'id': conversationId, 'other_name': person['name']},
          );
      await _select(conversation);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  void _insertQuickReply(String text) {
    final selection = _composer.selection;
    final value = _composer.text;
    final start = selection.isValid ? selection.start : value.length;
    final end = selection.isValid ? selection.end : value.length;
    final prefix = value.substring(0, start);
    final suffix = value.substring(end);
    final separator = prefix.isEmpty || prefix.endsWith(' ') ? '' : ' ';
    final next = '$prefix$separator$text$suffix';
    _composer.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: (prefix + separator + text).length));
  }

  Future<void> _muteConversation() async {
    if (_conversationId == null) return;
    final minutes = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Mute notifications', style: TextStyle(fontWeight: FontWeight.w800))),
        for (final option in const [(60, 'For 1 hour'), (480, 'For 8 hours'), (1440, 'For 1 day'), (0, 'Unmute')])
          ListTile(title: Text(option.$2), onTap: () => Navigator.pop(context, option.$1)),
      ])),
    );
    if (minutes == null) return;
    try {
      await ChatApi.mute(_conversationId!, minutes);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(minutes == 0 ? 'Notifications unmuted.' : 'Notifications muted.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(builder: (context, size) {
      final wide = size.maxWidth >= 1280;
      final mobile = size.maxWidth < 720;
      return Container(color: const Color(0xFFF5F7FB), child: Row(children: [
        if (!mobile || _conversationId == null) SizedBox(width: mobile ? size.maxWidth : 350, child: _Inbox(items: _conversations, selected: _conversationId, onSelect: _select, onNewMessage: _startConversation)),
        if (!mobile) const VerticalDivider(width: 1),
        Expanded(child: _conversationId == null ? const _EmptyChat() : _Conversation(name: _name, messages: _messages, myId: _myId, threadLoading: _threadLoading, threadError: _threadError, composer: _composer, sending: _sending, onSend: _send, onAttach: _attach, onQuickReply: _insertQuickReply, onMute: _muteConversation, onBack: mobile ? () => setState(() => _conversationId = null) : null, detailsOpen: wide && _detailsOpen, onToggleDetails: wide ? () => setState(() => _detailsOpen = !_detailsOpen) : null)),
        if (wide) _AnimatedDetailsPanel(isOpen: _detailsOpen, conversationId: _conversationId, name: _name),
      ]));
    });
  }
}

class _AnimatedDetailsPanel extends StatelessWidget {
  const _AnimatedDetailsPanel({required this.isOpen, required this.conversationId, required this.name});

  final bool isOpen;
  final int? conversationId;
  final String name;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 240);

    return ClipRect(
      child: AnimatedAlign(
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerRight,
        widthFactor: isOpen ? 1 : 0,
        child: AnimatedOpacity(
          duration: duration,
          curve: Curves.easeOut,
          opacity: isOpen ? 1 : 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const VerticalDivider(width: 1),
              SizedBox(width: 340, child: _Details(conversationId: conversationId, name: name)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Inbox extends StatefulWidget {
  const _Inbox({required this.items, required this.selected, required this.onSelect, required this.onNewMessage});
  final List<Map<String, dynamic>> items;
  final int? selected;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final VoidCallback onNewMessage;

  @override
  State<_Inbox> createState() => _InboxState();
}

class _InboxState extends State<_Inbox> {
  final _search = TextEditingController();
  String _filter = 'All';

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = widget.items.where((item) {
      final unread = int.tryParse('${item['unread_count'] ?? 0}') ?? 0;
      final isDirect = '${item['conversation_type'] ?? 'direct'}' == 'direct';
      final matchesFilter = switch (_filter) {
        'Unread' => unread > 0,
        'Direct' => isDirect,
        'Teams' => !isDirect,
        _ => true,
      };
      final searchable = '${item['other_name'] ?? ''} ${item['latest_body'] ?? ''}'.toLowerCase();
      return matchesFilter && (query.isEmpty || searchable.contains(query));
    }).toList();

    return Material(color: Colors.white, child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(18,18,16,12), child: Row(children: [
        const Text('Messages', style: TextStyle(fontSize: 19,fontWeight: FontWeight.w800,color:Color(0xFF0F2348))), const SizedBox(width: 8),
        _Badge('${widget.items.fold<int>(0, (n,x) => n + (int.tryParse('${x['unread_count'] ?? 0}') ?? 0))} unread'), const Spacer(),
        IconButton(tooltip: 'New message', onPressed: widget.onNewMessage, icon: const Icon(Icons.edit_square), style: IconButton.styleFrom(backgroundColor: const Color(0xFF1A56DB),foregroundColor: Colors.white,shape: RoundedRectangleBorder(borderRadius:BorderRadius.circular(10)))),
      ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal:16), child: TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search,size:20,color:Color(0xFF637493)), hintText:'Search conversations…', hintStyle:TextStyle(fontSize:13), isDense:true, filled:true,fillColor:Color(0xFFF8FAFD), border:OutlineInputBorder(borderRadius:BorderRadius.all(Radius.circular(10)),borderSide:BorderSide(color:Color(0xFFDCE5F2)))))),
      const SizedBox(height: 14),
      Container(padding:const EdgeInsets.fromLTRB(16,0,16,10),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:Color(0xFFE9EEF5)))),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween, children:['All','Unread','Teams','Direct'].map((label) => _Filter(label, _filter == label, () => setState(() => _filter = label))).toList())),
      Expanded(child: visible.isEmpty ? const Center(child: Text('No conversations found.')) : ListView.builder(itemCount: visible.length, itemBuilder: (_, index) { final item=visible[index]; final unread=int.tryParse('${item['unread_count'] ?? 0}') ?? 0; final active=item['id']==widget.selected; final name=(item['other_name'] ?? 'Conversation').toString(); return Material(color:active?const Color(0xFFEAF1FF):Colors.white,child:InkWell(onTap:()=>widget.onSelect(item),child:Container(padding:const EdgeInsets.symmetric(horizontal:16,vertical:12),decoration:BoxDecoration(border:Border(left:BorderSide(color:active?const Color(0xFF1A56DB):Colors.transparent,width:3),bottom:const BorderSide(color:Color(0xFFF0F3F8))),),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Stack(clipBehavior:Clip.none,children:[CircleAvatar(radius:21,backgroundColor:const Color(0xFF4F61F6),foregroundColor:Colors.white,child:Text(name.isEmpty ? '?' : name[0].toUpperCase(),style:const TextStyle(fontWeight:FontWeight.w800))),const Positioned(right:-1,bottom:-1,child:CircleAvatar(radius:5,backgroundColor:Color(0xFF08A978)))]),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(name,style:TextStyle(fontWeight:FontWeight.w800,color:active?const Color(0xFF1559CD):const Color(0xFF17223B)))),Text(_relativeTime(item['updated_at']),style:const TextStyle(fontSize:11,color:Color(0xFF1A56DB),fontWeight:FontWeight.w700))]),const SizedBox(height:4),Text(item['latest_kind']=='system'?'Attendance update':item['latest_body']??'',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,color:Color(0xFF526581))),const SizedBox(height:5),Text('${item['conversation_type'] == 'group' ? 'Team conversation' : 'Direct message'}',style:const TextStyle(fontSize:10,color:Color(0xFF94A3B8)))])),if(unread>0)Padding(padding:const EdgeInsets.only(left:8,top:12),child:_Badge('$unread'))])))); })),
    ]));
  }
}

class _Badge extends StatelessWidget { const _Badge(this.text); final String text; @override Widget build(BuildContext c)=>Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),decoration:BoxDecoration(color:const Color(0xFFEBF2FE),borderRadius:BorderRadius.circular(12),border:Border.all(color:const Color(0xFFBFDBFE))),child:Text(text,style:const TextStyle(fontSize:10,color:Color(0xFF1A56DB),fontWeight:FontWeight.w800))); }
class _Filter extends StatelessWidget { const _Filter(this.label,this.active,this.onTap); final String label; final bool active; final VoidCallback onTap; @override Widget build(BuildContext c)=>Semantics(button:true,selected:active,label:'Filter conversations by $label',child:InkWell(onTap:onTap,borderRadius:BorderRadius.circular(7),child:Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),decoration:BoxDecoration(color:active?const Color(0xFFEBF2FE):Colors.transparent,borderRadius:BorderRadius.circular(7)),child:Text(label,style:TextStyle(fontSize:11,fontWeight:active?FontWeight.w800:FontWeight.w600,color:active?const Color(0xFF1A56DB):const Color(0xFF64748B)))))); }
class _EmptyChat extends StatelessWidget { const _EmptyChat(); @override Widget build(BuildContext c)=>const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[CircleAvatar(radius:34,backgroundColor:Color(0xFFE9F1FF),child:Icon(Icons.forum_outlined,size:32,color:Color(0xFF1A56DB))),SizedBox(height:18),Text('Choose a conversation',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800,color:Color(0xFF0F2348))),SizedBox(height:6),Text('Select a person from Messages to start chatting.',style:TextStyle(color:Color(0xFF64748B)))])); }

class _Conversation extends StatefulWidget {
  const _Conversation({required this.name,required this.messages,required this.myId,required this.threadLoading,required this.threadError,required this.composer,required this.sending,required this.onSend,required this.onAttach,required this.onQuickReply,required this.onMute,this.onBack,this.onToggleDetails,this.detailsOpen = false});
  final String name; final List<Map<String,dynamic>> messages; final int? myId; final bool threadLoading; final String? threadError; final TextEditingController composer; final bool sending; final VoidCallback onSend,onAttach,onMute; final ValueChanged<String> onQuickReply; final VoidCallback? onBack; final VoidCallback? onToggleDetails; final bool detailsOpen;

  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  final _scrollController = ScrollController();
  bool _nearBottom = true;
  bool _hasNewMessagesBelow = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant _Conversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldLastId = oldWidget.messages.isEmpty ? null : oldWidget.messages.last['id'];
    final newLastId = widget.messages.isEmpty ? null : widget.messages.last['id'];
    if (newLastId == null || newLastId == oldLastId) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_nearBottom) {
        _scrollToLatest(animate: oldLastId != null);
      } else if (!_hasNewMessagesBelow) {
        setState(() => _hasNewMessagesBelow = true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final nearBottom = _scrollController.position.maxScrollExtent - _scrollController.offset <= 72;
    if (nearBottom == _nearBottom && (!nearBottom || !_hasNewMessagesBelow)) return;
    setState(() {
      _nearBottom = nearBottom;
      if (nearBottom) _hasNewMessagesBelow = false;
    });
  }

  void _scrollToLatest({bool animate = true}) {
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToLatest(animate: animate);
      });
      return;
    }
    final target = _scrollController.position.maxScrollExtent;
    if (animate && !MediaQuery.disableAnimationsOf(context)) {
      _scrollController.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
    } else {
      _scrollController.jumpTo(target);
    }
    if (_hasNewMessagesBelow) setState(() => _hasNewMessagesBelow = false);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(height:76,color:Colors.white,padding:const EdgeInsets.symmetric(horizontal:22),child:Row(children:[if(widget.onBack!=null)IconButton(onPressed:widget.onBack,icon:const Icon(Icons.arrow_back)),CircleAvatar(radius:21,backgroundColor:const Color(0xFFDBEAFE),foregroundColor:const Color(0xFF1A56DB),child:Text(widget.name.isEmpty ? '?' : widget.name[0].toUpperCase(),style:const TextStyle(fontWeight:FontWeight.w800))),const SizedBox(width:12),Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Flexible(child:Text(widget.name,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16,color:Color(0xFF0F2348)))),const SizedBox(width:8),Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),decoration:BoxDecoration(color:const Color(0xFFECFDF5),borderRadius:BorderRadius.circular(7),border:Border.all(color:const Color(0xFFA7F3D0))),child:const Text('Available',style:TextStyle(fontSize:10,color:Color(0xFF047857),fontWeight:FontWeight.w800)))]),const SizedBox(height:3),const Text('Direct message · Attendance-enabled chat',style:TextStyle(fontSize:12,color:Color(0xFF64748B)))])),PopupMenuButton<String>(onSelected:(value){if(value=='mute')widget.onMute();},icon:const Icon(Icons.more_horiz,color:Color(0xFF64748B)),itemBuilder:(_)=>const [PopupMenuItem(value:'profile',child:Text('Open employee profile')),PopupMenuItem(value:'attendance',child:Text('View attendance')),PopupMenuItem(value:'mute',child:Text('Mute notifications'))]),if(widget.onToggleDetails != null) IconButton(tooltip: widget.detailsOpen ? 'Hide conversation details' : 'Show conversation details',onPressed:widget.onToggleDetails,icon:Icon(Icons.info_outline,color:widget.detailsOpen?const Color(0xFF0F4CC7):const Color(0xFF1A56DB)))])),
    const Divider(height:1,color:Color(0xFFE4EAF3)), const Padding(padding:EdgeInsets.only(top:16),child:Text('TODAY',style:TextStyle(fontSize:10,letterSpacing:1,fontWeight:FontWeight.w800,color:Color(0xFF71809B))),),
    Expanded(child:widget.threadLoading?const Center(child:CircularProgressIndicator()):widget.threadError!=null?Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('Could not load messages.\n${widget.threadError}',textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFFB91C1C))))):widget.messages.isEmpty?const Center(child:Text('No messages yet. Start the conversation.',style:TextStyle(color:Color(0xFF64748B)))):Stack(children:[ListView.builder(controller:_scrollController,padding:const EdgeInsets.fromLTRB(34,14,34,18),itemCount:widget.messages.length,itemBuilder:(_,i)=>_Message(message:widget.messages[i],mine:widget.messages[i]['sender_user_id']==widget.myId)),if(!_nearBottom)Positioned(left:0,right:0,bottom:18,child:Center(child:Semantics(button:true,label:'Jump to latest messages',child:Tooltip(message:_hasNewMessagesBelow?'New messages':'Latest messages',child:Material(color:const Color(0xFF1A56DB),shape:const CircleBorder(),elevation:5,child:InkWell(onTap:_scrollToLatest,customBorder:const CircleBorder(),child:const SizedBox(width:44,height:44,child:Icon(Icons.keyboard_arrow_down_rounded,color:Colors.white,size:29)))))))) ])),
    _Composer(controller:widget.composer,sending:widget.sending,onSend:widget.onSend,onAttach:widget.onAttach,onQuickReply:widget.onQuickReply),
  ]);
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.mine});
  final Map<String, dynamic> message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final isSystem = message['message_kind'] == 'system';
    final files = (message['attachments'] as List?) ?? const [];
    if (isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.fromLTRB(14,12,14,10), constraints: const BoxConstraints(maxWidth: 455),
          decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFDE3A4)), boxShadow:const [BoxShadow(color:Color(0x100F2348),blurRadius:8,offset:Offset(0,2))]),
          child: Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Container(padding:const EdgeInsets.all(6),decoration:const BoxDecoration(color:Color(0xFFFFE8B3),shape:BoxShape.circle),child:const Icon(Icons.fact_check_outlined,size:16,color:Color(0xFFB7791F))),const SizedBox(width:8),const Expanded(child:Text('Attendance update',style:TextStyle(fontWeight:FontWeight.w800,fontSize:12,color:Color(0xFF744210)))),Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),decoration:BoxDecoration(color:const Color(0xFFFFEDD5),borderRadius:BorderRadius.circular(6)),child:const Text('SYSTEM',style:TextStyle(fontSize:9,fontWeight:FontWeight.w800,color:Color(0xFFB45309))))]),const SizedBox(height:10),Text('${message['body'] ?? ''}',style:const TextStyle(fontSize:12,color:Color(0xFF5B4B21),height:1.35)),const SizedBox(height:9),const Divider(height:1,color:Color(0xFFFDE6AD)),const SizedBox(height:7),const Text('Recorded automatically from attendance activity',style:TextStyle(fontSize:10,color:Color(0xFF8A7435)))]),
        ),
      );
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(13), constraints: const BoxConstraints(maxWidth: 570),
        decoration: BoxDecoration(color: mine ? const Color(0xFF1A56DB) : Colors.white, borderRadius: BorderRadius.only(topLeft:const Radius.circular(15),topRight:const Radius.circular(15),bottomLeft:Radius.circular(mine?15:4),bottomRight:Radius.circular(mine?4:15)), border: mine ? null : Border.all(color: const Color(0xFFDDE4F0)),boxShadow:mine?null:const [BoxShadow(color:Color(0x0B0F2348),blurRadius:6,offset:Offset(0,2))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${message['body'] ?? ''}', style: TextStyle(color: mine ? Colors.white : const Color(0xFF17223B))),
          for (final file in files) _AttachmentLine(file: Map<String, dynamic>.from(file as Map), mine: mine),
          const SizedBox(height: 4),
          if (mine) Text(message['delivery_status'] == 'read' ? 'Read' : 'Sent', style: const TextStyle(fontSize: 10, color: Colors.white70)),
        ]),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller,required this.sending,required this.onSend,required this.onAttach,required this.onQuickReply});
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend,onAttach;
  final ValueChanged<String> onQuickReply;

  void _showEmojiPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(child: SizedBox(height: 320, child: EmojiPicker(onEmojiSelected: (_, emoji) { final selection = controller.selection; final position = selection.isValid ? selection.start : controller.text.length; controller.value = controller.value.copyWith(text: controller.text.replaceRange(position, selection.isValid ? selection.end : position, emoji.emoji), selection: TextSelection.collapsed(offset: position + emoji.emoji.length)); }))),
    );
  }

  @override Widget build(BuildContext c)=>Container(color:Colors.white,padding:const EdgeInsets.fromLTRB(22,12,22,16),child:SafeArea(top:false,child:Container(padding:const EdgeInsets.fromLTRB(12,10,12,8),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(16),border:Border.all(color:const Color(0xFFD7E1F0)),boxShadow:const [BoxShadow(color:Color(0x120F2348),blurRadius:12,offset:Offset(0,4))]),child:Column(children:[Align(alignment:Alignment.centerLeft,child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[_QuickChip('Shift schedule',onQuickReply),const SizedBox(width:6),_QuickChip('Request overtime',onQuickReply),const SizedBox(width:6),_QuickChip('Apply leave',onQuickReply)]))),const Divider(height:17,color:Color(0xFFE9EEF5)),Row(children:[IconButton(tooltip:'Attach a file',onPressed:sending?null:onAttach,icon:const Icon(Icons.attach_file,color:Color(0xFF526581))),IconButton(tooltip:'Emoji',onPressed:sending?null:()=>_showEmojiPicker(c),icon:const Icon(Icons.emoji_emotions_outlined,color:Color(0xFF526581))),Expanded(child:TextField(controller:controller,onSubmitted:(_)=>onSend(),minLines:1,maxLines:4,decoration:const InputDecoration(hintText:'Write a message…',hintStyle:TextStyle(color:Color(0xFF8A9AB4)),isDense:true,border:InputBorder.none))),const SizedBox(width:8),FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:const Color(0xFF1A56DB),padding:const EdgeInsets.symmetric(horizontal:14,vertical:12),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),onPressed:sending?null:onSend,icon:sending?const SizedBox(width:15,height:15,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Icon(Icons.send,size:16),label:const Text('Send'))])]))));
}
class _QuickChip extends StatelessWidget { const _QuickChip(this.label,this.onTap); final String label; final ValueChanged<String> onTap; @override Widget build(BuildContext c)=>InkWell(onTap:()=>onTap(label),borderRadius:BorderRadius.circular(8),child:Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),decoration:BoxDecoration(color:const Color(0xFFF5F8FE),borderRadius:BorderRadius.circular(8),border:Border.all(color:const Color(0xFFE0E9F7))),child:Text(label,style:const TextStyle(fontSize:10,color:Color(0xFF486181),overflow:TextOverflow.ellipsis)))); }

class _AttachmentLine extends StatelessWidget {
  const _AttachmentLine({required this.file, required this.mine});
  final Map<String, dynamic> file;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final filename = '${file['original_name'] ?? 'Attachment'}';
    final lower = filename.toLowerCase();
    final isPdf = lower.endsWith('.pdf');
    final url = file['url'] ?? file['storage_key'];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: url == null ? null : () async {
        final launched = await launchUrl(Uri.parse(ApiConfig.mediaUrl('$url')), mode: LaunchMode.platformDefault);
        if (!launched && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to open this attachment.')));
      },
      child: Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(color: mine ? const Color(0x1FFFFFFF) : const Color(0xFFF6F9FE),borderRadius: BorderRadius.circular(10),border: Border.all(color: mine ? const Color(0x44FFFFFF) : const Color(0xFFDCE6F4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(7),decoration: BoxDecoration(color: isPdf ? const Color(0xFFFFE4E6) : (mine ? const Color(0x33FFFFFF) : const Color(0xFFE7F0FF)),borderRadius: BorderRadius.circular(8)),child: Icon(isPdf ? Icons.picture_as_pdf_outlined : Icons.insert_drive_file_outlined,size: 18,color: isPdf ? const Color(0xFFE11D48) : (mine ? Colors.white : const Color(0xFF1A56DB)))),
        const SizedBox(width: 8),
        Flexible(child: Text(filename,maxLines: 1,overflow: TextOverflow.ellipsis,style: TextStyle(fontSize: 11,fontWeight: FontWeight.w700,color: mine ? Colors.white : const Color(0xFF1B3765)))),
      ]),
    ));
  }
}

class _Details extends StatefulWidget {
  const _Details({required this.conversationId, required this.name});
  final int? conversationId;
  final String name;
  @override State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  String _tab = 'Overview';
  late Future<List<Map<String, dynamic>>> _attachments;

  @override
  void initState() { super.initState(); _attachments = _loadAttachments(); }

  @override
  void didUpdateWidget(covariant _Details oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) setState(() => _attachments = _loadAttachments());
  }

  Future<List<Map<String, dynamic>>> _loadAttachments() async => widget.conversationId == null ? [] : ChatApi.attachments(widget.conversationId!);

  @override
  Widget build(BuildContext context) => Material(color:Colors.white,child:ListView(padding:const EdgeInsets.all(20),children:[
    const Text('Conversation Details',style:TextStyle(fontSize:16,fontWeight:FontWeight.w800)),
    const SizedBox(height:20),
    const Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[_Action(Icons.call_outlined,'Audio'),_Action(Icons.videocam_outlined,'Video'),_Action(Icons.search,'Search'),_Action(Icons.notifications_off_outlined,'Mute')]),
    const Divider(height:36),
    Wrap(spacing:4,runSpacing:4,children:['Overview','Files','Attendance','Permissions'].map((tab)=>ChoiceChip(label:Text(tab),selected:_tab==tab,onSelected:(_)=>setState(()=>_tab=tab),selectedColor:const Color(0xFFEBF2FE),labelStyle:TextStyle(fontSize:11,fontWeight:FontWeight.w700,color:_tab==tab?const Color(0xFF1A56DB):const Color(0xFF64748B)))).toList()),
    const Divider(height:24),
    if(_tab=='Overview') ...[const Text('Conversation',style:TextStyle(fontSize:11,color:Color(0xFF94A3B8),fontWeight:FontWeight.w800)),const SizedBox(height:8),Text(widget.name.isEmpty?'Direct message':widget.name,style:const TextStyle(fontWeight:FontWeight.w700)),const SizedBox(height:22),const Text('Pinned reference',style:TextStyle(fontSize:11,color:Color(0xFF94A3B8),fontWeight:FontWeight.w800)),const SizedBox(height:8),const Text('No pinned references yet.',style:TextStyle(fontWeight:FontWeight.w700)),const SizedBox(height:22),const Text('Shared media & docs',style:TextStyle(color:Color(0xFF1A56DB),fontWeight:FontWeight.w800)),const SizedBox(height:8),const Text('Open the Files tab to browse all shared attachments.',style:TextStyle(fontSize:12,color:Color(0xFF64748B)))],
    if(_tab=='Files') FutureBuilder<List<Map<String,dynamic>>>(future:_attachments,builder:(context,snapshot){if(snapshot.connectionState!=ConnectionState.done)return const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator()));if(snapshot.hasError)return Padding(padding:const EdgeInsets.all(12),child:Text('Could not load files: ${snapshot.error}',style:const TextStyle(fontSize:12,color:Color(0xFFB91C1C))));final List<Map<String,dynamic>> files=snapshot.data??const [];if(files.isEmpty)return const Padding(padding:EdgeInsets.only(top:12),child:Text('No files have been shared in this conversation.',style:TextStyle(fontSize:12,color:Color(0xFF64748B))));return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${files.length} shared file${files.length==1?'':'s'}',style:const TextStyle(fontSize:11,color:Color(0xFF94A3B8),fontWeight:FontWeight.w800)),for(final file in files)_AttachmentLine(file:file,mine:false)]);}),
    if(_tab=='Attendance') const _DetailsNotice(icon:Icons.lock_outline,text:'Attendance details are available only through the authorized attendance view.'),
    if(_tab=='Permissions') const _DetailsNotice(icon:Icons.shield_outlined,text:'Conversation permissions are managed by your organization.'),
  ]));
}

class _DetailsNotice extends StatelessWidget { const _DetailsNotice({required this.icon,required this.text}); final IconData icon; final String text; @override Widget build(BuildContext c)=>Padding(padding:const EdgeInsets.only(top:16),child:Column(children:[Icon(icon,color:const Color(0xFF64748B)),const SizedBox(height:10),Text(text,textAlign:TextAlign.center,style:const TextStyle(fontSize:12,color:Color(0xFF64748B)))])); }
class _Action extends StatelessWidget { const _Action(this.icon,this.label); final IconData icon;final String label; @override Widget build(BuildContext c)=>Column(children:[CircleAvatar(radius:18,backgroundColor:const Color(0xFFF1F5F9),child:Icon(icon,size:18,color:const Color(0xFF1A56DB))),const SizedBox(height:5),Text(label,style:const TextStyle(fontSize:10))]); }
class _Stat extends StatelessWidget { const _Stat(this.label); final String label; @override Widget build(BuildContext c)=>Container(width:140,padding:const EdgeInsets.all(12),decoration:BoxDecoration(border:Border.all(color:const Color(0xFFE2E8F0)),borderRadius:BorderRadius.circular(10)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(fontSize:11,color:Color(0xFF64748B))),const SizedBox(height:8),const Text('Not available',style:TextStyle(fontSize:12,fontWeight:FontWeight.w700))])); }
