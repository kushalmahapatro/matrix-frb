// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConversationState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ConversationState()';
}


}

/// @nodoc
class $ConversationStateCopyWith<$Res>  {
$ConversationStateCopyWith(ConversationState _, $Res Function(ConversationState) __);
}


/// Adds pattern-matching-related methods to [ConversationState].
extension ConversationStatePatterns on ConversationState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ConversationStateLoading value)?  loading,TResult Function( ConversationStateWaitingForInvite value)?  waitingForInvite,TResult Function( RoomStateLoaded value)?  loaded,TResult Function( RoomStateError value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ConversationStateLoading() when loading != null:
return loading(_that);case ConversationStateWaitingForInvite() when waitingForInvite != null:
return waitingForInvite(_that);case RoomStateLoaded() when loaded != null:
return loaded(_that);case RoomStateError() when error != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ConversationStateLoading value)  loading,required TResult Function( ConversationStateWaitingForInvite value)  waitingForInvite,required TResult Function( RoomStateLoaded value)  loaded,required TResult Function( RoomStateError value)  error,}){
final _that = this;
switch (_that) {
case ConversationStateLoading():
return loading(_that);case ConversationStateWaitingForInvite():
return waitingForInvite(_that);case RoomStateLoaded():
return loaded(_that);case RoomStateError():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ConversationStateLoading value)?  loading,TResult? Function( ConversationStateWaitingForInvite value)?  waitingForInvite,TResult? Function( RoomStateLoaded value)?  loaded,TResult? Function( RoomStateError value)?  error,}){
final _that = this;
switch (_that) {
case ConversationStateLoading() when loading != null:
return loading(_that);case ConversationStateWaitingForInvite() when waitingForInvite != null:
return waitingForInvite(_that);case RoomStateLoaded() when loaded != null:
return loaded(_that);case RoomStateError() when error != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  loading,TResult Function()?  waitingForInvite,TResult Function( List<Message> messages,  ConversationInfo roomInfo)?  loaded,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ConversationStateLoading() when loading != null:
return loading();case ConversationStateWaitingForInvite() when waitingForInvite != null:
return waitingForInvite();case RoomStateLoaded() when loaded != null:
return loaded(_that.messages,_that.roomInfo);case RoomStateError() when error != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  loading,required TResult Function()  waitingForInvite,required TResult Function( List<Message> messages,  ConversationInfo roomInfo)  loaded,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case ConversationStateLoading():
return loading();case ConversationStateWaitingForInvite():
return waitingForInvite();case RoomStateLoaded():
return loaded(_that.messages,_that.roomInfo);case RoomStateError():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  loading,TResult? Function()?  waitingForInvite,TResult? Function( List<Message> messages,  ConversationInfo roomInfo)?  loaded,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case ConversationStateLoading() when loading != null:
return loading();case ConversationStateWaitingForInvite() when waitingForInvite != null:
return waitingForInvite();case RoomStateLoaded() when loaded != null:
return loaded(_that.messages,_that.roomInfo);case RoomStateError() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class ConversationStateLoading implements ConversationState {
  const ConversationStateLoading();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationStateLoading);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ConversationState.loading()';
}


}




/// @nodoc


class ConversationStateWaitingForInvite implements ConversationState {
  const ConversationStateWaitingForInvite();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationStateWaitingForInvite);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ConversationState.waitingForInvite()';
}


}




/// @nodoc


class RoomStateLoaded implements ConversationState {
  const RoomStateLoaded({required final  List<Message> messages, required this.roomInfo}): _messages = messages;
  

 final  List<Message> _messages;
 List<Message> get messages {
  if (_messages is EqualUnmodifiableListView) return _messages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_messages);
}

 final  ConversationInfo roomInfo;

/// Create a copy of ConversationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomStateLoadedCopyWith<RoomStateLoaded> get copyWith => _$RoomStateLoadedCopyWithImpl<RoomStateLoaded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoomStateLoaded&&const DeepCollectionEquality().equals(other._messages, _messages)&&(identical(other.roomInfo, roomInfo) || other.roomInfo == roomInfo));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_messages),roomInfo);

@override
String toString() {
  return 'ConversationState.loaded(messages: $messages, roomInfo: $roomInfo)';
}


}

/// @nodoc
abstract mixin class $RoomStateLoadedCopyWith<$Res> implements $ConversationStateCopyWith<$Res> {
  factory $RoomStateLoadedCopyWith(RoomStateLoaded value, $Res Function(RoomStateLoaded) _then) = _$RoomStateLoadedCopyWithImpl;
@useResult
$Res call({
 List<Message> messages, ConversationInfo roomInfo
});


$ConversationInfoCopyWith<$Res> get roomInfo;

}
/// @nodoc
class _$RoomStateLoadedCopyWithImpl<$Res>
    implements $RoomStateLoadedCopyWith<$Res> {
  _$RoomStateLoadedCopyWithImpl(this._self, this._then);

  final RoomStateLoaded _self;
  final $Res Function(RoomStateLoaded) _then;

/// Create a copy of ConversationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? messages = null,Object? roomInfo = null,}) {
  return _then(RoomStateLoaded(
messages: null == messages ? _self._messages : messages // ignore: cast_nullable_to_non_nullable
as List<Message>,roomInfo: null == roomInfo ? _self.roomInfo : roomInfo // ignore: cast_nullable_to_non_nullable
as ConversationInfo,
  ));
}

/// Create a copy of ConversationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationInfoCopyWith<$Res> get roomInfo {
  
  return $ConversationInfoCopyWith<$Res>(_self.roomInfo, (value) {
    return _then(_self.copyWith(roomInfo: value));
  });
}
}

/// @nodoc


class RoomStateError implements ConversationState {
  const RoomStateError({required this.message});
  

 final  String message;

/// Create a copy of ConversationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomStateErrorCopyWith<RoomStateError> get copyWith => _$RoomStateErrorCopyWithImpl<RoomStateError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoomStateError&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'ConversationState.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $RoomStateErrorCopyWith<$Res> implements $ConversationStateCopyWith<$Res> {
  factory $RoomStateErrorCopyWith(RoomStateError value, $Res Function(RoomStateError) _then) = _$RoomStateErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$RoomStateErrorCopyWithImpl<$Res>
    implements $RoomStateErrorCopyWith<$Res> {
  _$RoomStateErrorCopyWithImpl(this._self, this._then);

  final RoomStateError _self;
  final $Res Function(RoomStateError) _then;

/// Create a copy of ConversationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(RoomStateError(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ConversationInfo {

 String get id; String get name; String get topic; int get memberCount; bool get isDirect; String? get avatarUrl;
/// Create a copy of ConversationInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationInfoCopyWith<ConversationInfo> get copyWith => _$ConversationInfoCopyWithImpl<ConversationInfo>(this as ConversationInfo, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationInfo&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.topic, topic) || other.topic == topic)&&(identical(other.memberCount, memberCount) || other.memberCount == memberCount)&&(identical(other.isDirect, isDirect) || other.isDirect == isDirect)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,topic,memberCount,isDirect,avatarUrl);

@override
String toString() {
  return 'ConversationInfo(id: $id, name: $name, topic: $topic, memberCount: $memberCount, isDirect: $isDirect, avatarUrl: $avatarUrl)';
}


}

/// @nodoc
abstract mixin class $ConversationInfoCopyWith<$Res>  {
  factory $ConversationInfoCopyWith(ConversationInfo value, $Res Function(ConversationInfo) _then) = _$ConversationInfoCopyWithImpl;
@useResult
$Res call({
 String id, String name, String topic, int memberCount, bool isDirect, String? avatarUrl
});




}
/// @nodoc
class _$ConversationInfoCopyWithImpl<$Res>
    implements $ConversationInfoCopyWith<$Res> {
  _$ConversationInfoCopyWithImpl(this._self, this._then);

  final ConversationInfo _self;
  final $Res Function(ConversationInfo) _then;

/// Create a copy of ConversationInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? topic = null,Object? memberCount = null,Object? isDirect = null,Object? avatarUrl = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,topic: null == topic ? _self.topic : topic // ignore: cast_nullable_to_non_nullable
as String,memberCount: null == memberCount ? _self.memberCount : memberCount // ignore: cast_nullable_to_non_nullable
as int,isDirect: null == isDirect ? _self.isDirect : isDirect // ignore: cast_nullable_to_non_nullable
as bool,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationInfo].
extension ConversationInfoPatterns on ConversationInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationInfo value)  $default,){
final _that = this;
switch (_that) {
case _ConversationInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationInfo value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String topic,  int memberCount,  bool isDirect,  String? avatarUrl)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationInfo() when $default != null:
return $default(_that.id,_that.name,_that.topic,_that.memberCount,_that.isDirect,_that.avatarUrl);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String topic,  int memberCount,  bool isDirect,  String? avatarUrl)  $default,) {final _that = this;
switch (_that) {
case _ConversationInfo():
return $default(_that.id,_that.name,_that.topic,_that.memberCount,_that.isDirect,_that.avatarUrl);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String topic,  int memberCount,  bool isDirect,  String? avatarUrl)?  $default,) {final _that = this;
switch (_that) {
case _ConversationInfo() when $default != null:
return $default(_that.id,_that.name,_that.topic,_that.memberCount,_that.isDirect,_that.avatarUrl);case _:
  return null;

}
}

}

/// @nodoc


class _ConversationInfo implements ConversationInfo {
  const _ConversationInfo({required this.id, required this.name, required this.topic, required this.memberCount, this.isDirect = false, this.avatarUrl});
  

@override final  String id;
@override final  String name;
@override final  String topic;
@override final  int memberCount;
@override@JsonKey() final  bool isDirect;
@override final  String? avatarUrl;

/// Create a copy of ConversationInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationInfoCopyWith<_ConversationInfo> get copyWith => __$ConversationInfoCopyWithImpl<_ConversationInfo>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationInfo&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.topic, topic) || other.topic == topic)&&(identical(other.memberCount, memberCount) || other.memberCount == memberCount)&&(identical(other.isDirect, isDirect) || other.isDirect == isDirect)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,topic,memberCount,isDirect,avatarUrl);

@override
String toString() {
  return 'ConversationInfo(id: $id, name: $name, topic: $topic, memberCount: $memberCount, isDirect: $isDirect, avatarUrl: $avatarUrl)';
}


}

/// @nodoc
abstract mixin class _$ConversationInfoCopyWith<$Res> implements $ConversationInfoCopyWith<$Res> {
  factory _$ConversationInfoCopyWith(_ConversationInfo value, $Res Function(_ConversationInfo) _then) = __$ConversationInfoCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String topic, int memberCount, bool isDirect, String? avatarUrl
});




}
/// @nodoc
class __$ConversationInfoCopyWithImpl<$Res>
    implements _$ConversationInfoCopyWith<$Res> {
  __$ConversationInfoCopyWithImpl(this._self, this._then);

  final _ConversationInfo _self;
  final $Res Function(_ConversationInfo) _then;

/// Create a copy of ConversationInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? topic = null,Object? memberCount = null,Object? isDirect = null,Object? avatarUrl = freezed,}) {
  return _then(_ConversationInfo(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,topic: null == topic ? _self.topic : topic // ignore: cast_nullable_to_non_nullable
as String,memberCount: null == memberCount ? _self.memberCount : memberCount // ignore: cast_nullable_to_non_nullable
as int,isDirect: null == isDirect ? _self.isDirect : isDirect // ignore: cast_nullable_to_non_nullable
as bool,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
