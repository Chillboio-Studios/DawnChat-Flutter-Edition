// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'gateway.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GatewayEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is GatewayEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'GatewayEvent()';
}


}

/// @nodoc
class $GatewayEventCopyWith<$Res>  {
$GatewayEventCopyWith(GatewayEvent _, $Res Function(GatewayEvent) __);
}


/// Adds pattern-matching-related methods to [GatewayEvent].
extension GatewayEventPatterns on GatewayEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( GatewayEvent_Open value)?  open,TResult Function( GatewayEvent_Text value)?  text,TResult Function( GatewayEvent_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case GatewayEvent_Open() when open != null:
return open(_that);case GatewayEvent_Text() when text != null:
return text(_that);case GatewayEvent_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( GatewayEvent_Open value)  open,required TResult Function( GatewayEvent_Text value)  text,required TResult Function( GatewayEvent_Closed value)  closed,}){
final _that = this;
switch (_that) {
case GatewayEvent_Open():
return open(_that);case GatewayEvent_Text():
return text(_that);case GatewayEvent_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( GatewayEvent_Open value)?  open,TResult? Function( GatewayEvent_Text value)?  text,TResult? Function( GatewayEvent_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case GatewayEvent_Open() when open != null:
return open(_that);case GatewayEvent_Text() when text != null:
return text(_that);case GatewayEvent_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  open,TResult Function( String field0)?  text,TResult Function( String field0)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case GatewayEvent_Open() when open != null:
return open();case GatewayEvent_Text() when text != null:
return text(_that.field0);case GatewayEvent_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  open,required TResult Function( String field0)  text,required TResult Function( String field0)  closed,}) {final _that = this;
switch (_that) {
case GatewayEvent_Open():
return open();case GatewayEvent_Text():
return text(_that.field0);case GatewayEvent_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  open,TResult? Function( String field0)?  text,TResult? Function( String field0)?  closed,}) {final _that = this;
switch (_that) {
case GatewayEvent_Open() when open != null:
return open();case GatewayEvent_Text() when text != null:
return text(_that.field0);case GatewayEvent_Closed() when closed != null:
return closed(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class GatewayEvent_Open extends GatewayEvent {
  const GatewayEvent_Open(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is GatewayEvent_Open);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'GatewayEvent.open()';
}


}




/// @nodoc


class GatewayEvent_Text extends GatewayEvent {
  const GatewayEvent_Text(this.field0): super._();
  

 final  String field0;

/// Create a copy of GatewayEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GatewayEvent_TextCopyWith<GatewayEvent_Text> get copyWith => _$GatewayEvent_TextCopyWithImpl<GatewayEvent_Text>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is GatewayEvent_Text&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'GatewayEvent.text(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $GatewayEvent_TextCopyWith<$Res> implements $GatewayEventCopyWith<$Res> {
  factory $GatewayEvent_TextCopyWith(GatewayEvent_Text value, $Res Function(GatewayEvent_Text) _then) = _$GatewayEvent_TextCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$GatewayEvent_TextCopyWithImpl<$Res>
    implements $GatewayEvent_TextCopyWith<$Res> {
  _$GatewayEvent_TextCopyWithImpl(this._self, this._then);

  final GatewayEvent_Text _self;
  final $Res Function(GatewayEvent_Text) _then;

/// Create a copy of GatewayEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(GatewayEvent_Text(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class GatewayEvent_Closed extends GatewayEvent {
  const GatewayEvent_Closed(this.field0): super._();
  

 final  String field0;

/// Create a copy of GatewayEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GatewayEvent_ClosedCopyWith<GatewayEvent_Closed> get copyWith => _$GatewayEvent_ClosedCopyWithImpl<GatewayEvent_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is GatewayEvent_Closed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'GatewayEvent.closed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $GatewayEvent_ClosedCopyWith<$Res> implements $GatewayEventCopyWith<$Res> {
  factory $GatewayEvent_ClosedCopyWith(GatewayEvent_Closed value, $Res Function(GatewayEvent_Closed) _then) = _$GatewayEvent_ClosedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$GatewayEvent_ClosedCopyWithImpl<$Res>
    implements $GatewayEvent_ClosedCopyWith<$Res> {
  _$GatewayEvent_ClosedCopyWithImpl(this._self, this._then);

  final GatewayEvent_Closed _self;
  final $Res Function(GatewayEvent_Closed) _then;

/// Create a copy of GatewayEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(GatewayEvent_Closed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
