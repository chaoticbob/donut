#
# Copyright (c) 2014-2020, NVIDIA CORPORATION. All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

set (NVRHI_DEFAULT_VK_REGISTER_OFFSETS
    --tRegShift 0
    --sRegShift 128
    --bRegShift 256
    --uRegShift 384)

# Generates a build target that will compile shaders for a given config file
# Usage:
#
# donut_compile_shaders(TARGET <generated build target name>
#                       CONFIG <shader-config-file>
#                       SOURCES <list>
#                       [FOLDER <folder-in-visual-studio-solution>]
#                       [OUTPUT_FORMAT (HEADER|BINARY)]
#                       [DXIL <dxil-output-path>]
#                       [DXBC <dxbc-output-path>]
#                       [SPIRV_DXC <spirv-output-path>]
#                       [COMPILER_OPTIONS_DXBC <string>]  -- arguments passed to ShaderMake
#                       [COMPILER_OPTIONS_DXIL <string>]
#                       [COMPILER_OPTIONS_SPIRV <string>]
#                       [COMPILER_OPTIONS_SPIRV_SLANG <string>]
#                       [BYPRODUCTS_DXBC <list>]          -- list of generated files without paths,
#                       [BYPRODUCTS_DXIL <list>]             needed to get correct incremental builds when
#                       [BYPRODUCTS_SPIRV <list>])           using static shaders with Ninja generator

function(donut_compile_shaders)
    set(options "")
    set(oneValueArgs TARGET CONFIG FOLDER OUTPUT_FORMAT DXIL DXBC SPIRV_DXC
                     COMPILER_OPTIONS_DXBC COMPILER_OPTIONS_DXIL COMPILER_OPTIONS_SPIRV COMPILER_OPTIONS_SPIRV_SLANG)
    set(multiValueArgs SOURCES BYPRODUCTS_DXBC BYPRODUCTS_DXIL BYPRODUCTS_SPIRV)
    cmake_parse_arguments(params "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if (NOT params_TARGET)
        message(FATAL_ERROR "donut_compile_shaders: TARGET argument missing")
    endif()
    if (NOT params_CONFIG)
        message(FATAL_ERROR "donut_compile_shaders: CONFIG argument missing")
    endif()

    # just add the source files to the project as documents, they are built by the script
    set_source_files_properties(${params_SOURCES} PROPERTIES VS_TOOL_OVERRIDE "None") 

    add_custom_target(${params_TARGET}
        DEPENDS ShaderMake
        SOURCES ${params_SOURCES})

    if (WIN32)
        set(use_api_arg --useAPI)
    else()
        set(use_api_arg "")
    endif()

    if ("${params_OUTPUT_FORMAT}" STREQUAL "HEADER")
        set(output_format_arg --headerBlob)
    elseif(("${params_OUTPUT_FORMAT}" STREQUAL "BINARY") OR ("${params_OUTPUT_FORMAT}" STREQUAL ""))
        set(output_format_arg --binaryBlob --outputExt .bin)
    else()
        message(FATAL_ERROR "donut_compile_shaders: unsupported OUTPUT_FORMAT = '${params_OUTPUT_FORMAT}'")
    endif()

    if (params_DXIL AND DONUT_WITH_DX12)
        if (NOT DXC_PATH)
            message(FATAL_ERROR "donut_compile_shaders: DXC not found --- please set DXC_PATH to the full path to the DXC binary")
        endif()
        
        set(compilerCommand ShaderMake
           --config ${params_CONFIG}
           --out ${params_DXIL}
           --platform DXIL
           ${output_format_arg}
           -I ${DONUT_SHADER_INCLUDE_DIR}
           --compiler "${DXC_PATH}"
           --shaderModel 6_5
           ${use_api_arg})

        separate_arguments(params_COMPILER_OPTIONS_DXIL NATIVE_COMMAND "${params_COMPILER_OPTIONS_DXIL}")

        list(APPEND compilerCommand ${params_COMPILER_OPTIONS_DXIL})

        if ("${params_BYPRODUCTS_DXIL}" STREQUAL "")
            add_custom_command(TARGET ${params_TARGET} PRE_BUILD COMMAND ${compilerCommand})
        else()
            set(byproducts_with_paths "")
            foreach(relative_path IN LISTS params_BYPRODUCTS_DXIL)
                list(APPEND byproducts_with_paths "${pasams_DXIL}/${relative_path}")
            endforeach()
            
            add_custom_command(TARGET ${params_TARGET} PRE_BUILD COMMAND ${compilerCommand} BYPRODUCTS "${byproducts_with_paths}")
        endif()
    endif()

    if (params_DXBC AND DONUT_WITH_DX11)
        if (NOT FXC_PATH)
            message(FATAL_ERROR "donut_compile_shaders: FXC not found --- please set FXC_PATH to the full path to the FXC binary")
        endif()
        
        set(compilerCommand ShaderMake
           --config ${params_CONFIG}
           --out ${params_DXBC}
           --platform DXBC
           ${output_format_arg}
           -I ${DONUT_SHADER_INCLUDE_DIR}
           --compiler "${FXC_PATH}"
           ${use_api_arg})

        separate_arguments(params_COMPILER_OPTIONS_DXBC NATIVE_COMMAND "${params_COMPILER_OPTIONS_DXBC}")

        list(APPEND compilerCommand ${params_COMPILER_OPTIONS_DXBC})

        if ("${params_BYPRODUCTS_DXBC}" STREQUAL "")
            add_custom_command(TARGET ${params_TARGET} PRE_BUILD COMMAND ${compilerCommand})
        else()
            set(byproducts_with_paths "")
            foreach(relative_path IN LISTS params_BYPRODUCTS_DXBC)
                list(APPEND byproducts_with_paths "${pasams_DXBC}/${relative_path}")
            endforeach()

            add_custom_command(TARGET ${params_TARGET} PRE_BUILD COMMAND ${compilerCommand} BYPRODUCTS "${byproducts_with_paths}")
        endif()
    endif()

    if (params_SPIRV_DXC AND DONUT_WITH_VULKAN)
        if (DONUT_WITH_SPIRV_SLANG)
            if (NOT SLANG_PATH)
                message(FATAL_ERROR "donut_compile_shaders: DONUT_WITH_SPIRV_SLANG specified but SLANG_PATH is missing --- please set SLANG_PATH to the full path to the slangc binary")
            endif()
            set(SPIRV_COMPILER_PATH "${SLANG_PATH}")
            set(SPIRV_ENABLE_SLANG "--slang")
            set(use_api_arg "")
        else()
            if (NOT DXC_SPIRV_PATH)
                message(FATAL_ERROR "donut_compile_shaders: DXC for SPIR-V not found --- please set DXC_SPIRV_PATH to the full path to the DXC binary")
            endif()
            set(SPIRV_COMPILER_PATH "${DXC_SPIRV_PATH}")
        endif()

        set(compilerCommand ShaderMake
           --config ${params_CONFIG}
           --out ${params_SPIRV_DXC}
           --platform SPIRV
           ${output_format_arg}
           -I ${DONUT_SHADER_INCLUDE_DIR}
           -D SPIRV
           --compiler "${SPIRV_COMPILER_PATH}"
           ${SPIRV_ENABLE_SLANG}
           --slangHLSL
           ${NVRHI_DEFAULT_VK_REGISTER_OFFSETS}
           --vulkanVersion 1.2
           --verbose
           --matrixRowMajor
           ${use_api_arg})

        if (DONUT_WITH_SPIRV_SLANG)
            separate_arguments(params_COMPILER_OPTIONS_SPIRV NATIVE_COMMAND "${params_COMPILER_OPTIONS_SPIRV_SLANG}")
        else()
            separate_arguments(params_COMPILER_OPTIONS_SPIRV NATIVE_COMMAND "${params_COMPILER_OPTIONS_SPIRV}")
        endif()

        list(APPEND compilerCommand ${params_COMPILER_OPTIONS_SPIRV})

        if ("${params_BYPRODUCTS_SPIRV}" STREQUAL "")
            add_custom_command(TARGET ${params_TARGET} PRE_BUILD COMMAND ${compilerCommand})
        else()
            set(byproducts_with_paths "")
            foreach(relative_path IN LISTS params_BYPRODUCTS_SPIRV)
                list(APPEND byproducts_with_paths "${params_SPIRV_DXC}/${relative_path}")
            endforeach()

            add_custom_command(TARGET ${params_TARGET} PRE_BUILD COMMAND ${compilerCommand} BYPRODUCTS "${byproducts_with_paths}")
        endif()
    endif()

    if(params_FOLDER)
        set_target_properties(${params_TARGET} PROPERTIES FOLDER ${params_FOLDER})
    endif()
endfunction()

# Generates a build target that will compile shaders for a given config file for all enabled Donut platforms.
#
# When OUTPUT_FORMAT is BINARY or is unspecified, the shaders will be placed into subdirectories of
# ${OUTPUT_BASE}, with names compatible with the FindDirectoryWithShaderBin framework function.
# When OUTPUT_FORMAT is HEADER, the shaders for all platforms will be placed into OUTPUT_BASE directly,
# with platform-specific extensions: .dxbc.h, .dxil.h, .spirv.h.
#
# The BYPRODUCTS_NO_EXT argument lists all generated files without extensions and without base paths.
# Similar to donut_compile_shaders, the list of byproducts is needed to get correct incremental builds
# when using static (.h) shaders with Ninja build system.
#
# Usage:
#
# donut_compile_shaders_all_platforms(TARGET <generated build target name>
#                                     CONFIG <shader-config-file>
#                                     SOURCES <list>
#                                     [FOLDER <folder-in-visual-studio-solution>]
#                                     [OUTPUT_FORMAT (HEADER|BINARY)]
#                                     [COMPILER_OPTIONS_DXBC <string>]  -- arguments passed to ShaderMake
#                                     [COMPILER_OPTIONS_DXIL <string>]
#                                     [COMPILER_OPTIONS_SPIRV <string>]
#                                     [COMPILER_OPTIONS_SPIRV_SLANG <string>]
#                                     [BYPRODUCTS_NO_EXT <list>])

function(donut_compile_shaders_all_platforms)
    set(options "")
    set(oneValueArgs TARGET CONFIG FOLDER OUTPUT_BASE OUTPUT_FORMAT COMPILER_OPTIONS_DXIL COMPILER_OPTIONS_DXBC COMPILER_OPTIONS_SPIRV COMPILER_OPTIONS_SPIRV_SLANG)
    set(multiValueArgs SOURCES BYPRODUCTS_NO_EXT)
    cmake_parse_arguments(params "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if (NOT params_TARGET)
        message(FATAL_ERROR "donut_compile_shaders_all_platforms: TARGET argument missing")
    endif()
    if (NOT params_CONFIG)
        message(FATAL_ERROR "donut_compile_shaders_all_platforms: CONFIG argument missing")
    endif()
    if (NOT params_OUTPUT_BASE)
        message(FATAL_ERROR "donut_compile_shaders_all_platforms: OUTPUT_BASE argument missing")
    endif()

    if ("${params_OUTPUT_FORMAT}" STREQUAL "HEADER")
        # Header/static compilation puts everything into one location and differentiates between platforms
        # using the .dxbc.h, .dxil.h, or .spirv.h extensions native to ShaderMake
        set(output_dxbc ${params_OUTPUT_BASE})
        set(output_dxil ${params_OUTPUT_BASE})
        set(output_spirv ${params_OUTPUT_BASE})
    else()
        # Binary compilation puts shaders into per-platform folders - legacy mode compatible with various apps
        set(output_dxbc ${params_OUTPUT_BASE}/dxbc)
        set(output_dxil ${params_OUTPUT_BASE}/dxil)
        set(output_spirv ${params_OUTPUT_BASE}/spirv)
    endif()

    set(byproducts_dxbc "")
    set(byproducts_dxil "")
    set(byproducts_spirv "")
    foreach(byproduct IN LISTS params_BYPRODUCTS_NO_EXT)
        list(APPEND byproducts_dxbc "${byproduct}.dxbc.h")
        list(APPEND byproducts_dxil "${byproduct}.dxil.h")
        list(APPEND byproducts_spirv "${byproduct}.spirv.h")
    endforeach()
    
    donut_compile_shaders(TARGET ${params_TARGET}
                          CONFIG ${params_CONFIG}
                          FOLDER ${params_FOLDER}
                          DXBC ${output_dxbc}
                          DXIL ${output_dxil}
                          SPIRV_DXC ${output_spirv}
                          OUTPUT_FORMAT ${params_OUTPUT_FORMAT}
                          COMPILER_OPTIONS_DXIL ${params_COMPILER_OPTIONS_DXIL}
                          COMPILER_OPTIONS_DXBC ${params_COMPILER_OPTIONS_DXBC}
                          COMPILER_OPTIONS_SPIRV ${params_COMPILER_OPTIONS_SPIRV}
                          COMPILER_OPTIONS_SPIRV_SLANG ${params_COMPILER_OPTIONS_SPIRV_SLANG}
                          SOURCES ${params_SOURCES}
                          BYPRODUCTS_DXBC ${byproducts_dxbc}
                          BYPRODUCTS_DXIL ${byproducts_dxil}
                          BYPRODUCTS_SPIRV ${byproducts_spirv})

endfunction()
