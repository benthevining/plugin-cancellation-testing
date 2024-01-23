cmake_minimum_required (VERSION 3.26.0 FATAL_ERROR)

project (
	PluginCancellationTesting
	VERSION 0.0.1
	LANGUAGES CXX
	DESCRIPTION "Utilities for audio cancellation testing of audio plugins with CTest"
	HOMEPAGE_URL "https://github.com/benthevining/plugin-cancellation-testing"
)

enable_testing()

include (FetchContent)

FetchContent_Declare (
	JUCE
	SYSTEM
	GIT_REPOSITORY "https://github.com/juce-framework/JUCE.git"
	GIT_TAG 7.0.9
	GIT_SHALLOW ON
	GIT_PROGRESS ON
	FIND_PACKAGE_ARGS 7.0.9
)

include ("${CMAKE_CURRENT_LIST_DIR}/CancellationTesting.cmake")

juce_add_console_app (audio-diff)

target_link_libraries (audio-diff PRIVATE juce::juce_audio_formats)

target_sources (audio-diff PRIVATE main.cpp)

add_executable (cancellation::audio_diff ALIAS audio-diff)

include (CMakePackageConfigHelpers)

write_basic_package_version_file (
	plugin-cancellation-config-version.cmake
	VERSION "${PROJECT_VERSION}"
	COMPATIBILITY SameMajorVersion
)

set (install_dest "${CMAKE_INSTALL_LIBDIR}/cmake/plugin-cancellation")

install (
	TARGETS audio-diff
	EXPORT PluginCancellationTargets
	COMPONENT plugin-cancellation
)

install (
	EXPORT PluginCancellationTargets
	NAMESPACE cancellation::
	COMPONENT plugin-cancellation
	DESTINATION "${install_dest}"
)

configure_package_config_file (
	config.cmake plugin-cancellation-config.cmake
	INSTALL_DESTINATION "${install_dest}"
)

install (FILES "${CMAKE_CURRENT_BINARY_DIR}/plugin-cancellation-config-version.cmake"
			   "${CMAKE_CURRENT_BINARY_DIR}/plugin-cancellation-config.cmake"
			   CancellationTesting.cmake
		 DESTINATION "${install_dest}"
		 COMPONENT plugin-cancellation
)

include (CPackComponent)

cpack_add_component (
	plugin-cancellation 
	DISPLAY_NAME "Audio cancellation testing code"
	DESCRIPTION "Code for audio cancellation testing of plugins (development component)"
)
