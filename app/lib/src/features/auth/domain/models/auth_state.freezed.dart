// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'auth_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AuthState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AuthState()';
}


}

/// @nodoc
class $AuthStateCopyWith<$Res>  {
$AuthStateCopyWith(AuthState _, $Res Function(AuthState) __);
}


/// Adds pattern-matching-related methods to [AuthState].
extension AuthStatePatterns on AuthState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AuthStateInitial value)?  initial,TResult Function( AuthStateLoading value)?  loading,TResult Function( AuthStateAuthenticated value)?  authenticated,TResult Function( AuthStateError value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AuthStateInitial() when initial != null:
return initial(_that);case AuthStateLoading() when loading != null:
return loading(_that);case AuthStateAuthenticated() when authenticated != null:
return authenticated(_that);case AuthStateError() when error != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AuthStateInitial value)  initial,required TResult Function( AuthStateLoading value)  loading,required TResult Function( AuthStateAuthenticated value)  authenticated,required TResult Function( AuthStateError value)  error,}){
final _that = this;
switch (_that) {
case AuthStateInitial():
return initial(_that);case AuthStateLoading():
return loading(_that);case AuthStateAuthenticated():
return authenticated(_that);case AuthStateError():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AuthStateInitial value)?  initial,TResult? Function( AuthStateLoading value)?  loading,TResult? Function( AuthStateAuthenticated value)?  authenticated,TResult? Function( AuthStateError value)?  error,}){
final _that = this;
switch (_that) {
case AuthStateInitial() when initial != null:
return initial(_that);case AuthStateLoading() when loading != null:
return loading(_that);case AuthStateAuthenticated() when authenticated != null:
return authenticated(_that);case AuthStateError() when error != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  initial,TResult Function( String message)?  loading,TResult Function()?  authenticated,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AuthStateInitial() when initial != null:
return initial();case AuthStateLoading() when loading != null:
return loading(_that.message);case AuthStateAuthenticated() when authenticated != null:
return authenticated();case AuthStateError() when error != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  initial,required TResult Function( String message)  loading,required TResult Function()  authenticated,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case AuthStateInitial():
return initial();case AuthStateLoading():
return loading(_that.message);case AuthStateAuthenticated():
return authenticated();case AuthStateError():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  initial,TResult? Function( String message)?  loading,TResult? Function()?  authenticated,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case AuthStateInitial() when initial != null:
return initial();case AuthStateLoading() when loading != null:
return loading(_that.message);case AuthStateAuthenticated() when authenticated != null:
return authenticated();case AuthStateError() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class AuthStateInitial implements AuthState {
  const AuthStateInitial();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthStateInitial);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AuthState.initial()';
}


}




/// @nodoc


class AuthStateLoading implements AuthState {
  const AuthStateLoading({required this.message});
  

 final  String message;

/// Create a copy of AuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuthStateLoadingCopyWith<AuthStateLoading> get copyWith => _$AuthStateLoadingCopyWithImpl<AuthStateLoading>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthStateLoading&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'AuthState.loading(message: $message)';
}


}

/// @nodoc
abstract mixin class $AuthStateLoadingCopyWith<$Res> implements $AuthStateCopyWith<$Res> {
  factory $AuthStateLoadingCopyWith(AuthStateLoading value, $Res Function(AuthStateLoading) _then) = _$AuthStateLoadingCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$AuthStateLoadingCopyWithImpl<$Res>
    implements $AuthStateLoadingCopyWith<$Res> {
  _$AuthStateLoadingCopyWithImpl(this._self, this._then);

  final AuthStateLoading _self;
  final $Res Function(AuthStateLoading) _then;

/// Create a copy of AuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(AuthStateLoading(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AuthStateAuthenticated implements AuthState {
  const AuthStateAuthenticated();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthStateAuthenticated);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AuthState.authenticated()';
}


}




/// @nodoc


class AuthStateError implements AuthState {
  const AuthStateError({required this.message});
  

 final  String message;

/// Create a copy of AuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuthStateErrorCopyWith<AuthStateError> get copyWith => _$AuthStateErrorCopyWithImpl<AuthStateError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthStateError&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'AuthState.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $AuthStateErrorCopyWith<$Res> implements $AuthStateCopyWith<$Res> {
  factory $AuthStateErrorCopyWith(AuthStateError value, $Res Function(AuthStateError) _then) = _$AuthStateErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$AuthStateErrorCopyWithImpl<$Res>
    implements $AuthStateErrorCopyWith<$Res> {
  _$AuthStateErrorCopyWithImpl(this._self, this._then);

  final AuthStateError _self;
  final $Res Function(AuthStateError) _then;

/// Create a copy of AuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(AuthStateError(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$LoginFormData {

 String get username; String get password; bool get isRegistration; bool get showPassword;
/// Create a copy of LoginFormData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoginFormDataCopyWith<LoginFormData> get copyWith => _$LoginFormDataCopyWithImpl<LoginFormData>(this as LoginFormData, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LoginFormData&&(identical(other.username, username) || other.username == username)&&(identical(other.password, password) || other.password == password)&&(identical(other.isRegistration, isRegistration) || other.isRegistration == isRegistration)&&(identical(other.showPassword, showPassword) || other.showPassword == showPassword));
}


@override
int get hashCode => Object.hash(runtimeType,username,password,isRegistration,showPassword);

@override
String toString() {
  return 'LoginFormData(username: $username, password: $password, isRegistration: $isRegistration, showPassword: $showPassword)';
}


}

/// @nodoc
abstract mixin class $LoginFormDataCopyWith<$Res>  {
  factory $LoginFormDataCopyWith(LoginFormData value, $Res Function(LoginFormData) _then) = _$LoginFormDataCopyWithImpl;
@useResult
$Res call({
 String username, String password, bool isRegistration, bool showPassword
});




}
/// @nodoc
class _$LoginFormDataCopyWithImpl<$Res>
    implements $LoginFormDataCopyWith<$Res> {
  _$LoginFormDataCopyWithImpl(this._self, this._then);

  final LoginFormData _self;
  final $Res Function(LoginFormData) _then;

/// Create a copy of LoginFormData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? username = null,Object? password = null,Object? isRegistration = null,Object? showPassword = null,}) {
  return _then(_self.copyWith(
username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,isRegistration: null == isRegistration ? _self.isRegistration : isRegistration // ignore: cast_nullable_to_non_nullable
as bool,showPassword: null == showPassword ? _self.showPassword : showPassword // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [LoginFormData].
extension LoginFormDataPatterns on LoginFormData {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LoginFormData value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LoginFormData() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LoginFormData value)  $default,){
final _that = this;
switch (_that) {
case _LoginFormData():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LoginFormData value)?  $default,){
final _that = this;
switch (_that) {
case _LoginFormData() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String username,  String password,  bool isRegistration,  bool showPassword)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LoginFormData() when $default != null:
return $default(_that.username,_that.password,_that.isRegistration,_that.showPassword);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String username,  String password,  bool isRegistration,  bool showPassword)  $default,) {final _that = this;
switch (_that) {
case _LoginFormData():
return $default(_that.username,_that.password,_that.isRegistration,_that.showPassword);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String username,  String password,  bool isRegistration,  bool showPassword)?  $default,) {final _that = this;
switch (_that) {
case _LoginFormData() when $default != null:
return $default(_that.username,_that.password,_that.isRegistration,_that.showPassword);case _:
  return null;

}
}

}

/// @nodoc


class _LoginFormData implements LoginFormData {
  const _LoginFormData({this.username = '', this.password = '', this.isRegistration = false, this.showPassword = false});
  

@override@JsonKey() final  String username;
@override@JsonKey() final  String password;
@override@JsonKey() final  bool isRegistration;
@override@JsonKey() final  bool showPassword;

/// Create a copy of LoginFormData
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LoginFormDataCopyWith<_LoginFormData> get copyWith => __$LoginFormDataCopyWithImpl<_LoginFormData>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LoginFormData&&(identical(other.username, username) || other.username == username)&&(identical(other.password, password) || other.password == password)&&(identical(other.isRegistration, isRegistration) || other.isRegistration == isRegistration)&&(identical(other.showPassword, showPassword) || other.showPassword == showPassword));
}


@override
int get hashCode => Object.hash(runtimeType,username,password,isRegistration,showPassword);

@override
String toString() {
  return 'LoginFormData(username: $username, password: $password, isRegistration: $isRegistration, showPassword: $showPassword)';
}


}

/// @nodoc
abstract mixin class _$LoginFormDataCopyWith<$Res> implements $LoginFormDataCopyWith<$Res> {
  factory _$LoginFormDataCopyWith(_LoginFormData value, $Res Function(_LoginFormData) _then) = __$LoginFormDataCopyWithImpl;
@override @useResult
$Res call({
 String username, String password, bool isRegistration, bool showPassword
});




}
/// @nodoc
class __$LoginFormDataCopyWithImpl<$Res>
    implements _$LoginFormDataCopyWith<$Res> {
  __$LoginFormDataCopyWithImpl(this._self, this._then);

  final _LoginFormData _self;
  final $Res Function(_LoginFormData) _then;

/// Create a copy of LoginFormData
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? username = null,Object? password = null,Object? isRegistration = null,Object? showPassword = null,}) {
  return _then(_LoginFormData(
username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,isRegistration: null == isRegistration ? _self.isRegistration : isRegistration // ignore: cast_nullable_to_non_nullable
as bool,showPassword: null == showPassword ? _self.showPassword : showPassword // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
