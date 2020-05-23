import 'package:analyzer/dart/element/element.dart';
import 'package:auto_route/auto_route_annotations.dart';
import 'package:auto_route_generator/route_config_resolver.dart';
import 'package:auto_route_generator/utils.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

const TypeChecker guardsChecker = TypeChecker.fromRuntime(GuardedBy);
const TypeChecker autoRouteChecker = TypeChecker.fromRuntime(AutoRoute);
const TypeChecker unknownRouteChecker = TypeChecker.fromRuntime(UnknownRoute);

// extracts route configs from class fields
class RouterConfigResolver {
  final RouteConfig _globConfig;
  final Resolver _resolver;

  RouterConfigResolver(this._globConfig, this._resolver);

  Future<RouteConfig> resolve(FieldElement field) async {
    final routeConfig = RouteConfig();
    final type = field.type;

    throwIf(
      type.element is! ClassElement,
      '${type.getDisplayString()} is not a class element',
      element: type.element,
    );

    final classElement = type.element as ClassElement;

    routeConfig.isUnknownRoute = unknownRouteChecker.hasAnnotationOfExact(field);

    if (routeConfig.isUnknownRoute) {
      final params = classElement.unnamedConstructor.parameters ?? [];
      throwIf(
        params.isEmpty || params.length > 1 || params.first.type.getDisplayString() != 'String',
        "UnknowRoute must have a defualt constructor with a positional String Parameter,"
        " MyUnknownRoute(String routeName",
        element: type.element,
      );
    }

    _extractRouteMetaData(routeConfig, field);

    guardsChecker.firstAnnotationOfExact(field)?.getField('guards')?.toListValue()?.map((g) => g.toTypeValue())?.forEach((guard) {
      routeConfig.guards.add(RouteGuardConfig(type: guard.getDisplayString(), import: getImport(guard.element)));
    });

    final import = getImport(type.element);

    if (import != null) {
      routeConfig.imports.add(import);
    }
    routeConfig.name = field.name;
    routeConfig.className = type.getDisplayString();

    routeConfig.hasWrapper = classElement.allSupertypes.map<String>((el) => el.getDisplayString()).contains('AutoRouteWrapper');

    final constructor = classElement.unnamedConstructor;

    if (constructor != null && constructor.parameters.isNotEmpty) {
      final paramResolver = RouteParameterResolver(_resolver);
      routeConfig.parameters = [];
      for (ParameterElement p in constructor.parameters) {
        routeConfig.parameters.add(await paramResolver.resolve(p));
      }
    }

    return routeConfig;
  }

  void _extractRouteMetaData(RouteConfig routeConfig, FieldElement field) {
    final routeAnnotation = autoRouteChecker.firstAnnotationOf(field);

    ConstantReader autoRoute;
    if (routeAnnotation != null) {
      autoRoute = ConstantReader(routeAnnotation);
      routeConfig.initial = autoRoute.peek('initial')?.boolValue;
    }
    if (autoRoute == null || routeConfig.initial == true) {
      routeConfig.routeType = _globConfig.routeType;
      if (_globConfig.routeType == RouteType.custom) {
        routeConfig.transitionBuilder = _globConfig.transitionBuilder;
        routeConfig.durationInMilliseconds = _globConfig.durationInMilliseconds;
        routeConfig.customRouteBarrierDismissible = _globConfig.customRouteBarrierDismissible;
        routeConfig.customRouteOpaque = _globConfig.customRouteOpaque;
      }
      return;
    }

    routeConfig.fullscreenDialog = autoRoute.peek('fullscreenDialog')?.boolValue;
    routeConfig.maintainState = autoRoute.peek('maintainState')?.boolValue;
    routeConfig.pathName = autoRoute.peek('name')?.stringValue;
    final returnType = autoRoute.peek('returnType')?.typeValue;
    if (returnType != null) {
      routeConfig.returnType = returnType.getDisplayString();
      final import = getImport(returnType.element);
      if (import != null) {
        routeConfig.imports.add(import);
      }
    }

    if ((autoRoute.instanceOf(TypeChecker.fromRuntime(MaterialRoute)))) {
      routeConfig.routeType = RouteType.material;
    } else if (autoRoute.instanceOf(TypeChecker.fromRuntime(CupertinoRoute))) {
      routeConfig.routeType = RouteType.cupertino;
      routeConfig.cupertinoNavTitle = autoRoute.peek('title')?.stringValue;
    } else if (autoRoute.instanceOf(TypeChecker.fromRuntime(AdaptiveRoute))) {
      routeConfig.routeType = RouteType.adaptive;
      routeConfig.cupertinoNavTitle = autoRoute.peek('cupertinoPageTitle')?.stringValue;
    } else if (autoRoute.instanceOf(TypeChecker.fromRuntime(CustomRoute))) {
      routeConfig.routeType = RouteType.custom;
      routeConfig.durationInMilliseconds = autoRoute.peek('durationInMilliseconds')?.intValue;
      routeConfig.customRouteOpaque = autoRoute.peek('opaque')?.boolValue;
      routeConfig.customRouteBarrierDismissible = autoRoute.peek('barrierDismissible')?.boolValue;
      final function = autoRoute.peek('transitionsBuilder')?.objectValue?.toFunctionValue();
      if (function != null) {
        final displayName = function.displayName.replaceFirst(RegExp('^_'), '');
        final functionName = (function.isStatic && function.enclosingElement?.displayName != null)
            ? '${function.enclosingElement.displayName}.$displayName'
            : displayName;

        var import;
        if (function.enclosingElement?.name != 'TransitionsBuilders') {
          import = getImport(function);
        }
        routeConfig.transitionBuilder = CustomTransitionBuilder(functionName, import);
      }
    } else {
      routeConfig.routeType = _globConfig.routeType;
    }
  }
}
