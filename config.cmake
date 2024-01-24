@PACKAGE_INIT@

include ("${CMAKE_CURRENT_LIST_DIR}/PluginCancellationTargets.cmake")

include ("${CMAKE_CURRENT_LIST_DIR}/CancellationTesting.cmake")

include (FeatureSummary)

set_package_properties (
	"${CMAKE_FIND_PACKAGE_NAME}" 
	PROPERTIES 
		URL "@plugin-cancellation_HOMEPAGE_URL@"
		DESCRIPTION "@plugin-cancellation_DESCRIPTION@"
)

check_required_components ("${CMAKE_FIND_PACKAGE_NAME}")
