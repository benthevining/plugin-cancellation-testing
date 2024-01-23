@PACKAGE_INIT@

include ("${CMAKE_CURRENT_LIST_DIR}/PluginCancellationTargets.cmake")

include ("${CMAKE_CURRENT_LIST_DIR}/CancellationTesting.cmake")

set (cancellation_find_package_name "${CMAKE_FIND_PACKAGE_NAME}")

include (FeatureSummary)

set_package_properties (
	"${cancellation_find_package_name}" 
	PROPERTIES 
		URL "@plugin-cancellation_HOMEPAGE_URL@"
		DESCRIPTION "@plugin-cancellation_DESCRIPTION@"
)

include (CMakeFindDependencyMacro)

find_dependency (JUCE 7.0.9)

check_required_components ("${cancellation_find_package_name}")

unset (cancellation_find_package_name)
