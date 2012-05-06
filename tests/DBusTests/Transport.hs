{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- Copyright (C) 2012 John Millikin <jmillikin@gmail.com>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

module DBusTests.Transport (test_Transport) where

import           Test.Chell

import           Control.Concurrent
import           Control.Monad.IO.Class (MonadIO, liftIO)
import qualified Data.ByteString
import           Data.ByteString (ByteString)
import qualified Data.Map as Map
import qualified Network as N
import qualified Network.Socket as NS
import           System.IO

import           DBus
import           DBus.Transport

import           DBusTests.Util

test_Transport :: Suite
test_Transport = suite "Transport"
	[ test_TransportOpen
	, test_TransportSendReceive
	]

test_TransportOpen :: Suite
test_TransportOpen = suite "transportOpen"
	[ test_OpenUnknown
	, test_OpenUnix
	, test_OpenTcp
	]

test_OpenUnknown :: Suite
test_OpenUnknown = assertions "unknown" $ do
	opened <- liftIO (transportOpen socketTransportOptions (address_ "noexist" Map.empty))
	$assert (left (opened :: Either TransportError SocketTransport))
	
	let Left err = opened
	$expect (equal err (TransportError "Unknown address method: \"noexist\""))

test_OpenUnix :: Suite
test_OpenUnix = suite "unix"
	[ test_OpenUnix_Path
	, test_OpenUnix_Abstract
	, test_OpenUnix_TooFew
	, test_OpenUnix_TooMany
	, test_OpenUnix_NotListening
	]

test_OpenUnix_Path :: Suite
test_OpenUnix_Path = assertions "path" $ do
	(addr, networkSocket) <- listenRandomUnixPath
	opened <- liftIO (transportOpen transportDefaultOptions addr)
	$assert (right (opened :: Either TransportError SocketTransport))
	let Right t = opened
	liftIO (transportClose t)
	liftIO (N.sClose networkSocket)

test_OpenUnix_Abstract :: Suite
test_OpenUnix_Abstract = assertions "abstract" $ do
	(addr, networkSocket) <- listenRandomUnixAbstract
	opened <- liftIO (transportOpen transportDefaultOptions addr)
	$assert (right (opened :: Either TransportError SocketTransport))
	let Right t = opened
	liftIO (transportClose t)
	liftIO (N.sClose networkSocket)

test_OpenUnix_TooFew :: Suite
test_OpenUnix_TooFew = assertions "too-few" $ do
	opened <- liftIO (transportOpen socketTransportOptions (address_ "unix" Map.empty))
	$assert (left (opened :: Either TransportError SocketTransport))
	
	let Left err = opened
	$expect (equal err (TransportError "One of 'path' or 'abstract' must be specified for the 'unix' transport."))

test_OpenUnix_TooMany :: Suite
test_OpenUnix_TooMany = assertions "too-many" $ do
	opened <- liftIO (transportOpen socketTransportOptions (address_ "unix" (Map.fromList
		[ ("path", "foo")
		, ("abstract", "bar")
		])))
	$assert (left (opened :: Either TransportError SocketTransport))
	
	let Left err = opened
	$expect (equal err (TransportError "Only one of 'path' or 'abstract' may be specified for the 'unix' transport."))

test_OpenUnix_NotListening :: Suite
test_OpenUnix_NotListening = assertions "too-many" $ do
	(addr, networkSocket) <- listenRandomUnixAbstract
	liftIO (NS.sClose networkSocket)
	opened <- liftIO (transportOpen socketTransportOptions addr)
	$assert (left (opened :: Either TransportError SocketTransport))
	
	let Left err = opened
	$expect (equal err (TransportError "connect: does not exist (Connection refused)"))

test_OpenTcp :: Suite
test_OpenTcp = suite "tcp"
	[ test_OpenTcp_IPv4
	, skipWhen noIPv6 test_OpenTcp_IPv6
	, test_OpenTcp_Unknown
	, test_OpenTcp_NoPort
	, test_OpenTcp_InvalidPort
	, test_OpenTcp_NoUsableAddresses
	, test_OpenTcp_NotListening
	]

test_OpenTcp_IPv4 :: Suite
test_OpenTcp_IPv4 = assertions "ipv4" $ do
	(addr, networkSocket) <- listenRandomIPv4
	opened <- liftIO (transportOpen transportDefaultOptions addr)
	$assert (right (opened :: Either TransportError SocketTransport))
	let Right t = opened
	liftIO (transportClose t)
	liftIO (N.sClose networkSocket)

test_OpenTcp_IPv6 :: Suite
test_OpenTcp_IPv6 = assertions "ipv6" $ do
	(addr, networkSocket) <- listenRandomIPv6
	opened <- liftIO (transportOpen transportDefaultOptions addr)
	$assert (right (opened :: Either TransportError SocketTransport))
	let Right t = opened
	liftIO (transportClose t)
	liftIO (N.sClose networkSocket)

test_OpenTcp_Unknown :: Suite
test_OpenTcp_Unknown = assertions "unknown-family" $ do
	opened <- liftIO (transportOpen socketTransportOptions (address_ "tcp" (Map.fromList
		[ ("family", "noexist")
		, ("port", "1234")
		])))
	$assert (left (opened :: Either TransportError SocketTransport))
	
	let Left err = opened
	$expect (equal err (TransportError "Unknown socket family for TCP transport: \"noexist\""))

test_OpenTcp_NoPort :: Suite
test_OpenTcp_NoPort = assertions "no-port" $ do
	opened <- liftIO (transportOpen socketTransportOptions (address_ "tcp" (Map.fromList
		[ ("family", "ipv4")
		])))
	$assert (left (opened :: Either TransportError SocketTransport))
	
	let Left err = opened
	$expect (equal err (TransportError "TCP transport requires the `port' parameter."))

test_OpenTcp_InvalidPort :: Suite
test_OpenTcp_InvalidPort = assertions "invalid-port" $ do
	opened <- liftIO (transportOpen socketTransportOptions (address_ "tcp" (Map.fromList
		[ ("family", "ipv4")
		, ("port", "123456")
		])))
	$assert (left (opened :: Either TransportError SocketTransport))
	
	let Left err = opened
	$expect (equal err (TransportError "Invalid socket port for TCP transport: \"123456\""))

test_OpenTcp_NoUsableAddresses :: Suite
test_OpenTcp_NoUsableAddresses = assertions "no-usable-addresses" $ do
	opened <- liftIO (transportOpen socketTransportOptions (address_ "tcp" (Map.fromList
		[ ("family", "ipv4")
		, ("port", "1234")
		, ("host", "256.256.256.256")
		])))
	$assert (left (opened :: Either TransportError SocketTransport))
	
	let Left err = opened
	$expect (equal err (TransportError "getAddrInfo: does not exist (No address associated with hostname)"))

test_OpenTcp_NotListening :: Suite
test_OpenTcp_NotListening = assertions "too-many" $ do
	(addr, networkSocket) <- listenRandomIPv4
	liftIO (NS.sClose networkSocket)
	opened <- liftIO (transportOpen socketTransportOptions addr)
	$assert (left (opened :: Either TransportError SocketTransport))
	
	let Left err = opened
	$expect (equal err (TransportError "connect: does not exist (Connection refused)"))

test_TransportSendReceive :: Suite
test_TransportSendReceive = assertions "send-receive" $ do
	(addr, networkSocket) <- listenRandomIPv4
	_ <- liftIO $ forkIO $ do
		(h, _, _) <- N.accept networkSocket
		hSetBuffering h NoBuffering
		
		bytes <- Data.ByteString.hGetLine h
		Data.ByteString.hPut h bytes
		hClose h
		NS.sClose networkSocket
	
	opened <- liftIO (transportOpen socketTransportOptions addr)
	$assert (right (opened :: Either TransportError SocketTransport))
	let Right t = opened
	
	liftIO (transportPut t "testing\n")
	bytes1 <- liftIO (transportGet t 2)
	bytes2 <- liftIO (transportGet t 100)
	
	$expect (equal bytes1 "te")
	$expect (equal bytes2 "sting")
	
	liftIO (transportClose t)
	liftIO (N.sClose networkSocket)

socketTransportOptions :: TransportOptions SocketTransport
socketTransportOptions = transportDefaultOptions

address_ :: ByteString -> Map.Map ByteString ByteString -> Address
address_ method params = case address method params of
	Just addr -> addr
	Nothing -> error "address_: invalid address"
