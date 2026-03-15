// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatState implements DiagnosticableTreeMixin {




@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'ChatState'))
    ;
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'ChatState()';
}


}

/// @nodoc
class $ChatStateCopyWith<$Res>  {
$ChatStateCopyWith(ChatState _, $Res Function(ChatState) __);
}


/// Adds pattern-matching-related methods to [ChatState].
extension ChatStatePatterns on ChatState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ChatStateLoading value)?  loading,TResult Function( ChatStateLoaded value)?  loaded,TResult Function( ChatStateError value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ChatStateLoading() when loading != null:
return loading(_that);case ChatStateLoaded() when loaded != null:
return loaded(_that);case ChatStateError() when error != null:
return error(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ChatStateLoading value)  loading,required TResult Function( ChatStateLoaded value)  loaded,required TResult Function( ChatStateError value)  error,}){
final _that = this;
switch (_that) {
case ChatStateLoading():
return loading(_that);case ChatStateLoaded():
return loaded(_that);case ChatStateError():
return error(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ChatStateLoading value)?  loading,TResult? Function( ChatStateLoaded value)?  loaded,TResult? Function( ChatStateError value)?  error,}){
final _that = this;
switch (_that) {
case ChatStateLoading() when loading != null:
return loading(_that);case ChatStateLoaded() when loaded != null:
return loaded(_that);case ChatStateError() when error != null:
return error(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  loading,TResult Function( List<Chat> rooms)?  loaded,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ChatStateLoading() when loading != null:
return loading();case ChatStateLoaded() when loaded != null:
return loaded(_that.rooms);case ChatStateError() when error != null:
return error(_that.message);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  loading,required TResult Function( List<Chat> rooms)  loaded,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case ChatStateLoading():
return loading();case ChatStateLoaded():
return loaded(_that.rooms);case ChatStateError():
return error(_that.message);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  loading,TResult? Function( List<Chat> rooms)?  loaded,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case ChatStateLoading() when loading != null:
return loading();case ChatStateLoaded() when loaded != null:
return loaded(_that.rooms);case ChatStateError() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class ChatStateLoading with DiagnosticableTreeMixin implements ChatState {
  const ChatStateLoading();
  





@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'ChatState.loading'))
    ;
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatStateLoading);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'ChatState.loading()';
}


}




/// @nodoc


class ChatStateLoaded with DiagnosticableTreeMixin implements ChatState {
  const ChatStateLoaded({required final  List<Chat> rooms}): _rooms = rooms;
  

 final  List<Chat> _rooms;
 List<Chat> get rooms {
  if (_rooms is EqualUnmodifiableListView) return _rooms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_rooms);
}


/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatStateLoadedCopyWith<ChatStateLoaded> get copyWith => _$ChatStateLoadedCopyWithImpl<ChatStateLoaded>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'ChatState.loaded'))
    ..add(DiagnosticsProperty('rooms', rooms));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatStateLoaded&&const DeepCollectionEquality().equals(other._rooms, _rooms));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_rooms));

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'ChatState.loaded(rooms: $rooms)';
}


}

/// @nodoc
abstract mixin class $ChatStateLoadedCopyWith<$Res> implements $ChatStateCopyWith<$Res> {
  factory $ChatStateLoadedCopyWith(ChatStateLoaded value, $Res Function(ChatStateLoaded) _then) = _$ChatStateLoadedCopyWithImpl;
@useResult
$Res call({
 List<Chat> rooms
});




}
/// @nodoc
class _$ChatStateLoadedCopyWithImpl<$Res>
    implements $ChatStateLoadedCopyWith<$Res> {
  _$ChatStateLoadedCopyWithImpl(this._self, this._then);

  final ChatStateLoaded _self;
  final $Res Function(ChatStateLoaded) _then;

/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? rooms = null,}) {
  return _then(ChatStateLoaded(
rooms: null == rooms ? _self._rooms : rooms // ignore: cast_nullable_to_non_nullable
as List<Chat>,
  ));
}


}

/// @nodoc


class ChatStateError with DiagnosticableTreeMixin implements ChatState {
  const ChatStateError({required this.message});
  

 final  String message;

/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatStateErrorCopyWith<ChatStateError> get copyWith => _$ChatStateErrorCopyWithImpl<ChatStateError>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'ChatState.error'))
    ..add(DiagnosticsProperty('message', message));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatStateError&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'ChatState.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $ChatStateErrorCopyWith<$Res> implements $ChatStateCopyWith<$Res> {
  factory $ChatStateErrorCopyWith(ChatStateError value, $Res Function(ChatStateError) _then) = _$ChatStateErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$ChatStateErrorCopyWithImpl<$Res>
    implements $ChatStateErrorCopyWith<$Res> {
  _$ChatStateErrorCopyWithImpl(this._self, this._then);

  final ChatStateError _self;
  final $Res Function(ChatStateError) _then;

/// Create a copy of ChatState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(ChatStateError(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$Chat implements DiagnosticableTreeMixin {

 String get id; String get name; String get lastMessage; ChatRoomStatus get status; DateTime? get lastActivity; int get unreadCount; bool get isDirect; String? get avatarUrl;
/// Create a copy of Chat
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatCopyWith<Chat> get copyWith => _$ChatCopyWithImpl<Chat>(this as Chat, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'Chat'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('name', name))..add(DiagnosticsProperty('lastMessage', lastMessage))..add(DiagnosticsProperty('status', status))..add(DiagnosticsProperty('lastActivity', lastActivity))..add(DiagnosticsProperty('unreadCount', unreadCount))..add(DiagnosticsProperty('isDirect', isDirect))..add(DiagnosticsProperty('avatarUrl', avatarUrl));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Chat&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.lastMessage, lastMessage) || other.lastMessage == lastMessage)&&(identical(other.status, status) || other.status == status)&&(identical(other.lastActivity, lastActivity) || other.lastActivity == lastActivity)&&(identical(other.unreadCount, unreadCount) || other.unreadCount == unreadCount)&&(identical(other.isDirect, isDirect) || other.isDirect == isDirect)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,lastMessage,status,lastActivity,unreadCount,isDirect,avatarUrl);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'Chat(id: $id, name: $name, lastMessage: $lastMessage, status: $status, lastActivity: $lastActivity, unreadCount: $unreadCount, isDirect: $isDirect, avatarUrl: $avatarUrl)';
}


}

/// @nodoc
abstract mixin class $ChatCopyWith<$Res>  {
  factory $ChatCopyWith(Chat value, $Res Function(Chat) _then) = _$ChatCopyWithImpl;
@useResult
$Res call({
 String id, String name, String lastMessage, ChatRoomStatus status, DateTime? lastActivity, int unreadCount, bool isDirect, String? avatarUrl
});




}
/// @nodoc
class _$ChatCopyWithImpl<$Res>
    implements $ChatCopyWith<$Res> {
  _$ChatCopyWithImpl(this._self, this._then);

  final Chat _self;
  final $Res Function(Chat) _then;

/// Create a copy of Chat
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? lastMessage = null,Object? status = null,Object? lastActivity = freezed,Object? unreadCount = null,Object? isDirect = null,Object? avatarUrl = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,lastMessage: null == lastMessage ? _self.lastMessage : lastMessage // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ChatRoomStatus,lastActivity: freezed == lastActivity ? _self.lastActivity : lastActivity // ignore: cast_nullable_to_non_nullable
as DateTime?,unreadCount: null == unreadCount ? _self.unreadCount : unreadCount // ignore: cast_nullable_to_non_nullable
as int,isDirect: null == isDirect ? _self.isDirect : isDirect // ignore: cast_nullable_to_non_nullable
as bool,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Chat].
extension ChatPatterns on Chat {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Chat value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Chat() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Chat value)  $default,){
final _that = this;
switch (_that) {
case _Chat():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Chat value)?  $default,){
final _that = this;
switch (_that) {
case _Chat() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String lastMessage,  ChatRoomStatus status,  DateTime? lastActivity,  int unreadCount,  bool isDirect,  String? avatarUrl)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Chat() when $default != null:
return $default(_that.id,_that.name,_that.lastMessage,_that.status,_that.lastActivity,_that.unreadCount,_that.isDirect,_that.avatarUrl);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String lastMessage,  ChatRoomStatus status,  DateTime? lastActivity,  int unreadCount,  bool isDirect,  String? avatarUrl)  $default,) {final _that = this;
switch (_that) {
case _Chat():
return $default(_that.id,_that.name,_that.lastMessage,_that.status,_that.lastActivity,_that.unreadCount,_that.isDirect,_that.avatarUrl);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String lastMessage,  ChatRoomStatus status,  DateTime? lastActivity,  int unreadCount,  bool isDirect,  String? avatarUrl)?  $default,) {final _that = this;
switch (_that) {
case _Chat() when $default != null:
return $default(_that.id,_that.name,_that.lastMessage,_that.status,_that.lastActivity,_that.unreadCount,_that.isDirect,_that.avatarUrl);case _:
  return null;

}
}

}

/// @nodoc


class _Chat extends Chat with DiagnosticableTreeMixin {
  const _Chat({required this.id, required this.name, required this.lastMessage, required this.status, this.lastActivity, this.unreadCount = 0, this.isDirect = false, this.avatarUrl}): super._();
  

@override final  String id;
@override final  String name;
@override final  String lastMessage;
@override final  ChatRoomStatus status;
@override final  DateTime? lastActivity;
@override@JsonKey() final  int unreadCount;
@override@JsonKey() final  bool isDirect;
@override final  String? avatarUrl;

/// Create a copy of Chat
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatCopyWith<_Chat> get copyWith => __$ChatCopyWithImpl<_Chat>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'Chat'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('name', name))..add(DiagnosticsProperty('lastMessage', lastMessage))..add(DiagnosticsProperty('status', status))..add(DiagnosticsProperty('lastActivity', lastActivity))..add(DiagnosticsProperty('unreadCount', unreadCount))..add(DiagnosticsProperty('isDirect', isDirect))..add(DiagnosticsProperty('avatarUrl', avatarUrl));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Chat&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.lastMessage, lastMessage) || other.lastMessage == lastMessage)&&(identical(other.status, status) || other.status == status)&&(identical(other.lastActivity, lastActivity) || other.lastActivity == lastActivity)&&(identical(other.unreadCount, unreadCount) || other.unreadCount == unreadCount)&&(identical(other.isDirect, isDirect) || other.isDirect == isDirect)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,lastMessage,status,lastActivity,unreadCount,isDirect,avatarUrl);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'Chat(id: $id, name: $name, lastMessage: $lastMessage, status: $status, lastActivity: $lastActivity, unreadCount: $unreadCount, isDirect: $isDirect, avatarUrl: $avatarUrl)';
}


}

/// @nodoc
abstract mixin class _$ChatCopyWith<$Res> implements $ChatCopyWith<$Res> {
  factory _$ChatCopyWith(_Chat value, $Res Function(_Chat) _then) = __$ChatCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String lastMessage, ChatRoomStatus status, DateTime? lastActivity, int unreadCount, bool isDirect, String? avatarUrl
});




}
/// @nodoc
class __$ChatCopyWithImpl<$Res>
    implements _$ChatCopyWith<$Res> {
  __$ChatCopyWithImpl(this._self, this._then);

  final _Chat _self;
  final $Res Function(_Chat) _then;

/// Create a copy of Chat
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? lastMessage = null,Object? status = null,Object? lastActivity = freezed,Object? unreadCount = null,Object? isDirect = null,Object? avatarUrl = freezed,}) {
  return _then(_Chat(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,lastMessage: null == lastMessage ? _self.lastMessage : lastMessage // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ChatRoomStatus,lastActivity: freezed == lastActivity ? _self.lastActivity : lastActivity // ignore: cast_nullable_to_non_nullable
as DateTime?,unreadCount: null == unreadCount ? _self.unreadCount : unreadCount // ignore: cast_nullable_to_non_nullable
as int,isDirect: null == isDirect ? _self.isDirect : isDirect // ignore: cast_nullable_to_non_nullable
as bool,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
