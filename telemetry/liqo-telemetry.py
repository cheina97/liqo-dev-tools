#!/usr/bin/env python3.9

import argparse
import boto3

from boto3.dynamodb.types import TypeDeserializer
from datetime import datetime, timedelta


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", help="The profile containing the AWS credentials", default="liqo")
    parser.add_argument("--region", help="The AWS region", default="eu-west-1")
    parser.add_argument("--filter-running", help="Whether to keep only clusters still running", action=argparse.BooleanOptionalAction)
    parser.add_argument("--filter-survivors", help="Whether to keep only clusters survived at least one day", action=argparse.BooleanOptionalAction)
    parser.add_argument("--filter-peered", help="Whether to keep only clusters with at least one peering active", action=argparse.BooleanOptionalAction)
    parser.add_argument("--filter-offloaded", help="Whether to keep only clusters with at least one namespace offloaded", action=argparse.BooleanOptionalAction)
    parser.add_argument("--include-countries", help="The comma separated list of countries to include (empty means all")
    parser.add_argument("--exclude-countries", help="The comma separated list of countries to exclude")
    parser.add_argument("--include-providers", help="The comma separated list of providers to include (empty means all)")
    parser.add_argument("--exclude-providers", help="The comma separated list of providers to exclude")
    args = parser.parse_args()

    include_countries = args.include_countries.split(",") if args.include_countries else []
    include_providers = args.include_providers.split(",") if args.include_providers else []
    exclude_countries = args.exclude_countries.split(",") if args.exclude_countries else []
    exclude_providers = args.exclude_providers.split(",") if args.exclude_providers else []

    session = boto3.Session(profile_name=args.profile)
    deserializer = TypeDeserializer()
    dynamodb = session.client('dynamodb', region_name=args.region)
    paginator = dynamodb.get_paginator('scan')

    first_entry = dict()
    for page in paginator.paginate(
        TableName='liqo-user-telemetry-first-record',
        ProjectionExpression='clusterID,#timestamp',
        ExpressionAttributeNames={"#timestamp": "timestamp"}
    ):
        for item in page['Items']:
            clusterID = deserializer.deserialize(item['clusterID'])
            timestamp = datetime.utcfromtimestamp(int(deserializer.deserialize(item['timestamp']) / 1000))
            first_entry[clusterID] = timestamp

    providers, providers_shown = dict(), dict()
    for page in paginator.paginate(TableName='liqo-user-telemetry-last-record'):
        for item in page['Items']:
            deserialized = {k: deserializer.deserialize(v) for k, v in item.items()}
            clusterID = deserialized['clusterID']
            timestamp = datetime.utcfromtimestamp(int(deserialized['timestamp']) / 1000)
            ip = deserialized['ip']
            telemetry = deserialized["telemetry"]

            delta = timestamp - first_entry[clusterID]
            star = "*" if datetime.now() - timestamp > timedelta(hours=25) else " "
            country = ip.get("geo", {}).get("country")
            city = ip.get("geo", {}).get("city")
            if not city:
                city = ip.get("geo", {}).get("timezone", "unknown")
            provider = telemetry.get("provider", "unknown")
            liqoVersion = telemetry.get("liqoVersion", "unknown")
            providers[provider] = providers.get(provider, 0) + 1

            incoming, outgoing, ns = 0, 0, 0
            for peering in telemetry.get("peeringInfo", []):
                outgoing += 1 if peering["outgoing"]["enabled"] else 0
                incoming += 1 if peering["incoming"]["enabled"] else 0
            ns = len(telemetry.get("namespacesInfo", []))

            if args.filter_running and star == "*":
                continue

            if args.filter_survivors and delta.days == 0:
                continue

            if args.filter_peered and outgoing + incoming == 0:
                continue

            if args.filter_offloaded and not ns:
                continue

            if (include_countries and country not in include_countries) or (include_providers and provider not in include_providers):
                continue

            if country in exclude_countries or provider in exclude_providers:
                continue

            providers_shown[provider] = providers_shown.get(provider, 0) + 1
            print(f"Provider: {provider:10s} - Version: {liqoVersion}, Outgoing: {outgoing}, Incoming: {incoming}, "
                  f"Namespaces: {ns} - Duration: {delta.days:3d}{star} days - Location: {country} ({city})")

    print("\nProviders summary (shown/total):")
    total, total_shown = 0, 0
    for provider, count in providers.items():
        total += count
        total_shown += providers_shown.get(provider, 0)
        print(f"{provider:10s}: {providers_shown.get(provider, 0):3d}/{count:3d}")
    print(f"total     : {total_shown:3d}/{total:3d}")
