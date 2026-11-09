// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'push.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PushEvent {

 Object get field0;



@override
bool operator ==(Object other) {
  final _this = this as PushEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PushEvent&&const DeepCollectionEquality().equals(other.field0, _this.field0));
}


@override
int get hashCode {
  final _this = this as PushEvent;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.field0));
}

@override
String toString() {
  final _this = this as PushEvent;
  return 'PushEvent(field0: ${_this.field0})';
}


}

/// @nodoc
class $PushEventCopyWith<$Res>  {
$PushEventCopyWith(PushEvent _, $Res Function(PushEvent) __);
}


/// Adds pattern-matching-related methods to [PushEvent].
extension PushEventPatterns on PushEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PushEvent_Registered value)?  registered,TResult Function( PushEvent_Notification value)?  notification,TResult Function( PushEvent_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PushEvent_Registered() when registered != null:
return registered(_that);case PushEvent_Notification() when notification != null:
return notification(_that);case PushEvent_Closed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PushEvent_Registered value)  registered,required TResult Function( PushEvent_Notification value)  notification,required TResult Function( PushEvent_Closed value)  closed,}){
final _that = this;
switch (_that) {
case PushEvent_Registered():
return registered(_that);case PushEvent_Notification():
return notification(_that);case PushEvent_Closed():
return closed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PushEvent_Registered value)?  registered,TResult? Function( PushEvent_Notification value)?  notification,TResult? Function( PushEvent_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case PushEvent_Registered() when registered != null:
return registered(_that);case PushEvent_Notification() when notification != null:
return notification(_that);case PushEvent_Closed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PushSubscription field0)?  registered,TResult Function( String field0)?  notification,TResult Function( String field0)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PushEvent_Registered() when registered != null:
return registered(_that.field0);case PushEvent_Notification() when notification != null:
return notification(_that.field0);case PushEvent_Closed() when closed != null:
return closed(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PushSubscription field0)  registered,required TResult Function( String field0)  notification,required TResult Function( String field0)  closed,}) {final _that = this;
switch (_that) {
case PushEvent_Registered():
return registered(_that.field0);case PushEvent_Notification():
return notification(_that.field0);case PushEvent_Closed():
return closed(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PushSubscription field0)?  registered,TResult? Function( String field0)?  notification,TResult? Function( String field0)?  closed,}) {final _that = this;
switch (_that) {
case PushEvent_Registered() when registered != null:
return registered(_that.field0);case PushEvent_Notification() when notification != null:
return notification(_that.field0);case PushEvent_Closed() when closed != null:
return closed(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class PushEvent_Registered extends PushEvent {
  const PushEvent_Registered(this.field0): super._();
  

@override final  PushSubscription field0;

/// Create a copy of PushEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PushEvent_RegisteredCopyWith<PushEvent_Registered> get copyWith => _$PushEvent_RegisteredCopyWithImpl<PushEvent_Registered>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PushEvent_Registered&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'PushEvent.registered(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PushEvent_RegisteredCopyWith<$Res> implements $PushEventCopyWith<$Res> {
  factory $PushEvent_RegisteredCopyWith(PushEvent_Registered value, $Res Function(PushEvent_Registered) _then) = _$PushEvent_RegisteredCopyWithImpl;
@useResult
$Res call({
 PushSubscription field0
});




}
/// @nodoc
class _$PushEvent_RegisteredCopyWithImpl<$Res>
    implements $PushEvent_RegisteredCopyWith<$Res> {
  _$PushEvent_RegisteredCopyWithImpl(this._self, this._then);

  final PushEvent_Registered _self;
  final $Res Function(PushEvent_Registered) _then;

/// Create a copy of PushEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PushEvent_Registered(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as PushSubscription,
  ));
}


}

/// @nodoc


class PushEvent_Notification extends PushEvent {
  const PushEvent_Notification(this.field0): super._();
  

@override final  String field0;

/// Create a copy of PushEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PushEvent_NotificationCopyWith<PushEvent_Notification> get copyWith => _$PushEvent_NotificationCopyWithImpl<PushEvent_Notification>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PushEvent_Notification&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'PushEvent.notification(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PushEvent_NotificationCopyWith<$Res> implements $PushEventCopyWith<$Res> {
  factory $PushEvent_NotificationCopyWith(PushEvent_Notification value, $Res Function(PushEvent_Notification) _then) = _$PushEvent_NotificationCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$PushEvent_NotificationCopyWithImpl<$Res>
    implements $PushEvent_NotificationCopyWith<$Res> {
  _$PushEvent_NotificationCopyWithImpl(this._self, this._then);

  final PushEvent_Notification _self;
  final $Res Function(PushEvent_Notification) _then;

/// Create a copy of PushEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PushEvent_Notification(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PushEvent_Closed extends PushEvent {
  const PushEvent_Closed(this.field0): super._();
  

@override final  String field0;

/// Create a copy of PushEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PushEvent_ClosedCopyWith<PushEvent_Closed> get copyWith => _$PushEvent_ClosedCopyWithImpl<PushEvent_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PushEvent_Closed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'PushEvent.closed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PushEvent_ClosedCopyWith<$Res> implements $PushEventCopyWith<$Res> {
  factory $PushEvent_ClosedCopyWith(PushEvent_Closed value, $Res Function(PushEvent_Closed) _then) = _$PushEvent_ClosedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$PushEvent_ClosedCopyWithImpl<$Res>
    implements $PushEvent_ClosedCopyWith<$Res> {
  _$PushEvent_ClosedCopyWithImpl(this._self, this._then);

  final PushEvent_Closed _self;
  final $Res Function(PushEvent_Closed) _then;

/// Create a copy of PushEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PushEvent_Closed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
