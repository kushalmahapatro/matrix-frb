// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'platform.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ClientError {
  String get msg;
  String? get details;

  /// Create a copy of ClientError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ClientErrorCopyWith<ClientError> get copyWith =>
      _$ClientErrorCopyWithImpl<ClientError>(this as ClientError, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ClientError &&
            (identical(other.msg, msg) || other.msg == msg) &&
            (identical(other.details, details) || other.details == details));
  }

  @override
  int get hashCode => Object.hash(runtimeType, msg, details);

  @override
  String toString() {
    return 'ClientError(msg: $msg, details: $details)';
  }
}

/// @nodoc
abstract mixin class $ClientErrorCopyWith<$Res> {
  factory $ClientErrorCopyWith(
          ClientError value, $Res Function(ClientError) _then) =
      _$ClientErrorCopyWithImpl;
  @useResult
  $Res call({String msg, String? details});
}

/// @nodoc
class _$ClientErrorCopyWithImpl<$Res> implements $ClientErrorCopyWith<$Res> {
  _$ClientErrorCopyWithImpl(this._self, this._then);

  final ClientError _self;
  final $Res Function(ClientError) _then;

  /// Create a copy of ClientError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? msg = null,
    Object? details = freezed,
  }) {
    return _then(_self.copyWith(
      msg: null == msg
          ? _self.msg
          : msg // ignore: cast_nullable_to_non_nullable
              as String,
      details: freezed == details
          ? _self.details
          : details // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [ClientError].
extension ClientErrorPatterns on ClientError {
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

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ClientError_Generic value)? generic,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case ClientError_Generic() when generic != null:
        return generic(_that);
      case _:
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

  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ClientError_Generic value) generic,
  }) {
    final _that = this;
    switch (_that) {
      case ClientError_Generic():
        return generic(_that);
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

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ClientError_Generic value)? generic,
  }) {
    final _that = this;
    switch (_that) {
      case ClientError_Generic() when generic != null:
        return generic(_that);
      case _:
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

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String msg, String? details)? generic,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case ClientError_Generic() when generic != null:
        return generic(_that.msg, _that.details);
      case _:
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

  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String msg, String? details) generic,
  }) {
    final _that = this;
    switch (_that) {
      case ClientError_Generic():
        return generic(_that.msg, _that.details);
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

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String msg, String? details)? generic,
  }) {
    final _that = this;
    switch (_that) {
      case ClientError_Generic() when generic != null:
        return generic(_that.msg, _that.details);
      case _:
        return null;
    }
  }
}

/// @nodoc

class ClientError_Generic extends ClientError {
  const ClientError_Generic({required this.msg, this.details}) : super._();

  @override
  final String msg;
  @override
  final String? details;

  /// Create a copy of ClientError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ClientError_GenericCopyWith<ClientError_Generic> get copyWith =>
      _$ClientError_GenericCopyWithImpl<ClientError_Generic>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ClientError_Generic &&
            (identical(other.msg, msg) || other.msg == msg) &&
            (identical(other.details, details) || other.details == details));
  }

  @override
  int get hashCode => Object.hash(runtimeType, msg, details);

  @override
  String toString() {
    return 'ClientError.generic(msg: $msg, details: $details)';
  }
}

/// @nodoc
abstract mixin class $ClientError_GenericCopyWith<$Res>
    implements $ClientErrorCopyWith<$Res> {
  factory $ClientError_GenericCopyWith(
          ClientError_Generic value, $Res Function(ClientError_Generic) _then) =
      _$ClientError_GenericCopyWithImpl;
  @override
  @useResult
  $Res call({String msg, String? details});
}

/// @nodoc
class _$ClientError_GenericCopyWithImpl<$Res>
    implements $ClientError_GenericCopyWith<$Res> {
  _$ClientError_GenericCopyWithImpl(this._self, this._then);

  final ClientError_Generic _self;
  final $Res Function(ClientError_Generic) _then;

  /// Create a copy of ClientError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? msg = null,
    Object? details = freezed,
  }) {
    return _then(ClientError_Generic(
      msg: null == msg
          ? _self.msg
          : msg // ignore: cast_nullable_to_non_nullable
              as String,
      details: freezed == details
          ? _self.details
          : details // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

// dart format on
