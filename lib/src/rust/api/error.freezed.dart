// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AppError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppError()';
}


}

/// @nodoc
class $AppErrorCopyWith<$Res>  {
$AppErrorCopyWith(AppError _, $Res Function(AppError) __);
}


/// Adds pattern-matching-related methods to [AppError].
extension AppErrorPatterns on AppError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AppError_NotFound value)?  notFound,TResult Function( AppError_InvalidInput value)?  invalidInput,TResult Function( AppError_Network value)?  network,TResult Function( AppError_FeedParse value)?  feedParse,TResult Function( AppError_Database value)?  database,TResult Function( AppError_Io value)?  io,TResult Function( AppError_Unauthorized value)?  unauthorized,TResult Function( AppError_Conflict value)?  conflict,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AppError_NotFound() when notFound != null:
return notFound(_that);case AppError_InvalidInput() when invalidInput != null:
return invalidInput(_that);case AppError_Network() when network != null:
return network(_that);case AppError_FeedParse() when feedParse != null:
return feedParse(_that);case AppError_Database() when database != null:
return database(_that);case AppError_Io() when io != null:
return io(_that);case AppError_Unauthorized() when unauthorized != null:
return unauthorized(_that);case AppError_Conflict() when conflict != null:
return conflict(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AppError_NotFound value)  notFound,required TResult Function( AppError_InvalidInput value)  invalidInput,required TResult Function( AppError_Network value)  network,required TResult Function( AppError_FeedParse value)  feedParse,required TResult Function( AppError_Database value)  database,required TResult Function( AppError_Io value)  io,required TResult Function( AppError_Unauthorized value)  unauthorized,required TResult Function( AppError_Conflict value)  conflict,}){
final _that = this;
switch (_that) {
case AppError_NotFound():
return notFound(_that);case AppError_InvalidInput():
return invalidInput(_that);case AppError_Network():
return network(_that);case AppError_FeedParse():
return feedParse(_that);case AppError_Database():
return database(_that);case AppError_Io():
return io(_that);case AppError_Unauthorized():
return unauthorized(_that);case AppError_Conflict():
return conflict(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AppError_NotFound value)?  notFound,TResult? Function( AppError_InvalidInput value)?  invalidInput,TResult? Function( AppError_Network value)?  network,TResult? Function( AppError_FeedParse value)?  feedParse,TResult? Function( AppError_Database value)?  database,TResult? Function( AppError_Io value)?  io,TResult? Function( AppError_Unauthorized value)?  unauthorized,TResult? Function( AppError_Conflict value)?  conflict,}){
final _that = this;
switch (_that) {
case AppError_NotFound() when notFound != null:
return notFound(_that);case AppError_InvalidInput() when invalidInput != null:
return invalidInput(_that);case AppError_Network() when network != null:
return network(_that);case AppError_FeedParse() when feedParse != null:
return feedParse(_that);case AppError_Database() when database != null:
return database(_that);case AppError_Io() when io != null:
return io(_that);case AppError_Unauthorized() when unauthorized != null:
return unauthorized(_that);case AppError_Conflict() when conflict != null:
return conflict(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String resource,  String id)?  notFound,TResult Function( String field0)?  invalidInput,TResult Function( String url,  int status,  String message)?  network,TResult Function( String url,  String message)?  feedParse,TResult Function( String field0)?  database,TResult Function( String field0)?  io,TResult Function()?  unauthorized,TResult Function( String field0)?  conflict,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AppError_NotFound() when notFound != null:
return notFound(_that.resource,_that.id);case AppError_InvalidInput() when invalidInput != null:
return invalidInput(_that.field0);case AppError_Network() when network != null:
return network(_that.url,_that.status,_that.message);case AppError_FeedParse() when feedParse != null:
return feedParse(_that.url,_that.message);case AppError_Database() when database != null:
return database(_that.field0);case AppError_Io() when io != null:
return io(_that.field0);case AppError_Unauthorized() when unauthorized != null:
return unauthorized();case AppError_Conflict() when conflict != null:
return conflict(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String resource,  String id)  notFound,required TResult Function( String field0)  invalidInput,required TResult Function( String url,  int status,  String message)  network,required TResult Function( String url,  String message)  feedParse,required TResult Function( String field0)  database,required TResult Function( String field0)  io,required TResult Function()  unauthorized,required TResult Function( String field0)  conflict,}) {final _that = this;
switch (_that) {
case AppError_NotFound():
return notFound(_that.resource,_that.id);case AppError_InvalidInput():
return invalidInput(_that.field0);case AppError_Network():
return network(_that.url,_that.status,_that.message);case AppError_FeedParse():
return feedParse(_that.url,_that.message);case AppError_Database():
return database(_that.field0);case AppError_Io():
return io(_that.field0);case AppError_Unauthorized():
return unauthorized();case AppError_Conflict():
return conflict(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String resource,  String id)?  notFound,TResult? Function( String field0)?  invalidInput,TResult? Function( String url,  int status,  String message)?  network,TResult? Function( String url,  String message)?  feedParse,TResult? Function( String field0)?  database,TResult? Function( String field0)?  io,TResult? Function()?  unauthorized,TResult? Function( String field0)?  conflict,}) {final _that = this;
switch (_that) {
case AppError_NotFound() when notFound != null:
return notFound(_that.resource,_that.id);case AppError_InvalidInput() when invalidInput != null:
return invalidInput(_that.field0);case AppError_Network() when network != null:
return network(_that.url,_that.status,_that.message);case AppError_FeedParse() when feedParse != null:
return feedParse(_that.url,_that.message);case AppError_Database() when database != null:
return database(_that.field0);case AppError_Io() when io != null:
return io(_that.field0);case AppError_Unauthorized() when unauthorized != null:
return unauthorized();case AppError_Conflict() when conflict != null:
return conflict(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class AppError_NotFound extends AppError {
  const AppError_NotFound({required this.resource, required this.id}): super._();
  

 final  String resource;
 final  String id;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppError_NotFoundCopyWith<AppError_NotFound> get copyWith => _$AppError_NotFoundCopyWithImpl<AppError_NotFound>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_NotFound&&(identical(other.resource, resource) || other.resource == resource)&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,resource,id);

@override
String toString() {
  return 'AppError.notFound(resource: $resource, id: $id)';
}


}

/// @nodoc
abstract mixin class $AppError_NotFoundCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $AppError_NotFoundCopyWith(AppError_NotFound value, $Res Function(AppError_NotFound) _then) = _$AppError_NotFoundCopyWithImpl;
@useResult
$Res call({
 String resource, String id
});




}
/// @nodoc
class _$AppError_NotFoundCopyWithImpl<$Res>
    implements $AppError_NotFoundCopyWith<$Res> {
  _$AppError_NotFoundCopyWithImpl(this._self, this._then);

  final AppError_NotFound _self;
  final $Res Function(AppError_NotFound) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? resource = null,Object? id = null,}) {
  return _then(AppError_NotFound(
resource: null == resource ? _self.resource : resource // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AppError_InvalidInput extends AppError {
  const AppError_InvalidInput(this.field0): super._();
  

 final  String field0;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppError_InvalidInputCopyWith<AppError_InvalidInput> get copyWith => _$AppError_InvalidInputCopyWithImpl<AppError_InvalidInput>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_InvalidInput&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AppError.invalidInput(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AppError_InvalidInputCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $AppError_InvalidInputCopyWith(AppError_InvalidInput value, $Res Function(AppError_InvalidInput) _then) = _$AppError_InvalidInputCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$AppError_InvalidInputCopyWithImpl<$Res>
    implements $AppError_InvalidInputCopyWith<$Res> {
  _$AppError_InvalidInputCopyWithImpl(this._self, this._then);

  final AppError_InvalidInput _self;
  final $Res Function(AppError_InvalidInput) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AppError_InvalidInput(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AppError_Network extends AppError {
  const AppError_Network({required this.url, required this.status, required this.message}): super._();
  

 final  String url;
 final  int status;
 final  String message;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppError_NetworkCopyWith<AppError_Network> get copyWith => _$AppError_NetworkCopyWithImpl<AppError_Network>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_Network&&(identical(other.url, url) || other.url == url)&&(identical(other.status, status) || other.status == status)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,url,status,message);

@override
String toString() {
  return 'AppError.network(url: $url, status: $status, message: $message)';
}


}

/// @nodoc
abstract mixin class $AppError_NetworkCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $AppError_NetworkCopyWith(AppError_Network value, $Res Function(AppError_Network) _then) = _$AppError_NetworkCopyWithImpl;
@useResult
$Res call({
 String url, int status, String message
});




}
/// @nodoc
class _$AppError_NetworkCopyWithImpl<$Res>
    implements $AppError_NetworkCopyWith<$Res> {
  _$AppError_NetworkCopyWithImpl(this._self, this._then);

  final AppError_Network _self;
  final $Res Function(AppError_Network) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,Object? status = null,Object? message = null,}) {
  return _then(AppError_Network(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AppError_FeedParse extends AppError {
  const AppError_FeedParse({required this.url, required this.message}): super._();
  

 final  String url;
 final  String message;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppError_FeedParseCopyWith<AppError_FeedParse> get copyWith => _$AppError_FeedParseCopyWithImpl<AppError_FeedParse>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_FeedParse&&(identical(other.url, url) || other.url == url)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,url,message);

@override
String toString() {
  return 'AppError.feedParse(url: $url, message: $message)';
}


}

/// @nodoc
abstract mixin class $AppError_FeedParseCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $AppError_FeedParseCopyWith(AppError_FeedParse value, $Res Function(AppError_FeedParse) _then) = _$AppError_FeedParseCopyWithImpl;
@useResult
$Res call({
 String url, String message
});




}
/// @nodoc
class _$AppError_FeedParseCopyWithImpl<$Res>
    implements $AppError_FeedParseCopyWith<$Res> {
  _$AppError_FeedParseCopyWithImpl(this._self, this._then);

  final AppError_FeedParse _self;
  final $Res Function(AppError_FeedParse) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,Object? message = null,}) {
  return _then(AppError_FeedParse(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AppError_Database extends AppError {
  const AppError_Database(this.field0): super._();
  

 final  String field0;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppError_DatabaseCopyWith<AppError_Database> get copyWith => _$AppError_DatabaseCopyWithImpl<AppError_Database>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_Database&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AppError.database(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AppError_DatabaseCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $AppError_DatabaseCopyWith(AppError_Database value, $Res Function(AppError_Database) _then) = _$AppError_DatabaseCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$AppError_DatabaseCopyWithImpl<$Res>
    implements $AppError_DatabaseCopyWith<$Res> {
  _$AppError_DatabaseCopyWithImpl(this._self, this._then);

  final AppError_Database _self;
  final $Res Function(AppError_Database) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AppError_Database(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AppError_Io extends AppError {
  const AppError_Io(this.field0): super._();
  

 final  String field0;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppError_IoCopyWith<AppError_Io> get copyWith => _$AppError_IoCopyWithImpl<AppError_Io>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_Io&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AppError.io(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AppError_IoCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $AppError_IoCopyWith(AppError_Io value, $Res Function(AppError_Io) _then) = _$AppError_IoCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$AppError_IoCopyWithImpl<$Res>
    implements $AppError_IoCopyWith<$Res> {
  _$AppError_IoCopyWithImpl(this._self, this._then);

  final AppError_Io _self;
  final $Res Function(AppError_Io) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AppError_Io(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AppError_Unauthorized extends AppError {
  const AppError_Unauthorized(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_Unauthorized);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppError.unauthorized()';
}


}




/// @nodoc


class AppError_Conflict extends AppError {
  const AppError_Conflict(this.field0): super._();
  

 final  String field0;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppError_ConflictCopyWith<AppError_Conflict> get copyWith => _$AppError_ConflictCopyWithImpl<AppError_Conflict>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_Conflict&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AppError.conflict(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AppError_ConflictCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $AppError_ConflictCopyWith(AppError_Conflict value, $Res Function(AppError_Conflict) _then) = _$AppError_ConflictCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$AppError_ConflictCopyWithImpl<$Res>
    implements $AppError_ConflictCopyWith<$Res> {
  _$AppError_ConflictCopyWithImpl(this._self, this._then);

  final AppError_Conflict _self;
  final $Res Function(AppError_Conflict) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AppError_Conflict(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
